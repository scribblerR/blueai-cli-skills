---
name: blueai-cli-core
description: >
  使用 blueai-cli 调用任意命令的通用底座与入口分发器。当 agent 要用 blueai-cli 干活、
  但不确定「有没有这个命令 / 命令路径是什么 / 该传哪些参数 / 结果怎么取 / 异步怎么收口 /
  报错怎么修」时，先用本 skill。它教的是所有命令共享的调用契约：
  用 `spec list` 找命令、`schema` 查参数、`--dry-run` 预检、读 `{ok,data,meta}` 信封、
  按 exit code 分流报错、`--async`+`task wait` 收口、批量 NDJSON。
  也是分发器：识别意图后路由到对应领域 skill（aigc 生成、social-data 社媒采集、
  media-storage 媒体存储、video-tools 视频处理、datahub LLM 批处理、auth 凭证配置）。
  任何「怎么用 blueai-cli」「blueai-cli 调用 / 报错 / 看不懂输出」「有没有 xx 命令」
  「这个命令参数怎么填」的意图，即使没点名具体领域，也优先用本 skill 起手——
  它能在最少轮数内把意图变成一条能跑通的命令，再决定是否下钻领域 skill。
---

# BlueAI CLI 通用调用底座

blueai-cli 是**自描述**的 YAML 驱动 CLI：所有命令、参数、必填项、异步配置都来自 OpenAPI spec，CLI 在启动时动态构建命令树。这意味着 agent **不需要猜**——查得到、可预检、信封统一。本 skill 教的是让你**少走轮次、一次调通**的通用契约，并在需要时把你路由到领域 skill。

> **核心心法：永远查、永远预检，绝不凭记忆硬写。** 浪费轮次的根因都是「猜」——猜路径（路径错→报错→重试）、猜参数名（漏必填→校验失败→重试）、猜输出字段（取错层→解析失败）。CLI 把这三件事都做成了可查的，下面的回路就是把「猜」换成「查」。

## 黄金回路：discover → fill → call →（async collect）

所有命令都走这套，按需停在任一步：

```bash
# ① discover：命令存不存在？路径是什么？同步还是异步？要不要传文件？
blueai-cli spec tree                                      # 树视图：先看全貌（内部到底有哪些能力、层级如何），orientation 首选
blueai-cli spec tree --service kling                      # 树视图按厂商收窄
blueai-cli spec list --path 'aigc.video.text2video.**'   # glob 按「段」匹配，** 匹配任意层级；别写子串如 *jimeng*（不命中）
blueai-cli spec list --service kling                      # 扁平列表：逐条拿 paths[]/async/multipart/method，按厂商过滤最稳
#   → 拿到每条命令的 paths[]（点分路径，就是你要调的）、async、multipart、method

# ② fill：这条命令要传哪些参数？哪些必填？枚举值是什么？
blueai-cli schema aigc.video.text2video.kling --resolve-refs
#   → 读 requestBody 段：每个参数的 type / enum / 中文 description / 必填

# ③ 预检：先 --dry-run 看 CLI 实际会发出的 HTTP body，参数名/形状对了再花真调用
blueai-cli aigc video text2video kling --params '{"model_name":"kling-v3","prompt":"..."}' --dry-run

# ④ call：去掉 --dry-run。异步命令默认前台轮询到终态才返回
blueai-cli aigc video text2video kling --params '{"model_name":"kling-v3","prompt":"..."}'
```

> **路径有两种写法，查和调正好相反——混用是「Unknown command / 路径不存在」的头号根因：**
>
> | 用途 | 写法 | 例子 | 写错的后果 |
> |---|---|---|---|
> | **调用动态命令** | **空格分段**（每段是一级子命令） | `blueai-cli aigc video text2video kling` | 写成点分 `aigc.video.…kling` → `Unknown command` |
> | **`spec` / `schema` / `skill show` 查询** | **完整点分路径当一个参数** | `blueai-cli schema aigc.video.text2video.kling` | 写成空格 → 只把 `aigc` 当路径 → `not_found` |
>
> **多段版本叶子尤其要注意**：调用是 `… jimeng v4`（空格），不是 `jimeng.v4`。
> 记法：**`spec list` 的 `paths[]` 拿到的点分串，原样喂给 `schema`；真要调用时把点全换成空格。**

### `schema` 的关键陷阱

`schema <path>` 顶层的 `bodyParams` 是参数名速览，里面的 `schema` 字段**保留 `$ref`**（如 `{"$ref":"#/components/schemas/Prompt"}`），看不到真正的约束。**要看展开后的 enum / 中文描述 / 必填，加 `--resolve-refs` 并读 `requestBody` 段**——那里才是参数约束的权威来源，且永远最新。厂商 model_id 内嵌日期戳、版本迭代极快，**别凭记忆或本 skill 抄 model_id**，一律以 `schema --resolve-refs` 实时为准。

## 输出信封（所有命令统一）

成功 → stdout：

```json
{
  "ok": true,
  "data": { ... },     // ← 后端返回的原始 body（CLI 不裁剪）
  "meta": { "service": "kling", "path": "aigc.video.text2video.kling" }
}
```

失败 → **stderr**，且**始终是信封**（不会裸抛）：

```json
{ "ok": false, "error": { "type": "...", "message": "...", "reason": "...", "hint": "..." } }
```

> **铁律：业务 payload 常在双层 data，但分服务、且 `task wait` 还会再包一层。**
>
> - **直接调用 / `--async` 提交回执**：`data` 是后端原始 body，后端**通常**又包一层 `{code,message,data}`，所以 task_id 多在 `.data.data.task_id`、状态在 `.data.data.status`、产物 URL 在 `.data.data.*`。但**层数分服务**——有的后端是单层（task_id 直接在 `.data.task_id`，如即梦）。**一律以 `schema <path> --resolve-refs` 的 responseBody / `asyncConfig.taskIdField` 为准，别假设。**
> - **从 `task wait` 收结果**：每个任务被再包成 `{id, label, ok, result, error}`——**任务 ID 在顶层 `.id`**，后端原始 body 在 `.result` 里。所以产物字段是 `.result.…`（ndjson 每行）或 `.data[i].result.…`（`--format json`）；若该服务是双层，再下钻到 `.result.data.*`。
> - 成功看 stdout、失败看 stderr——agent 解析时分开读。

## 报错：按 exit code + error.type 分流

退出码本身就是分诊信号，先看码再看 `error.type` / `error.reason`：

| exit | error.type | 含义 | 修正 |
|---|---|---|---|
| 0 | — | 成功 | — |
| 2 | `validation` | CLI 端参数校验失败（漏必填、类型错、控制字符） | 对照 `schema --resolve-refs` 补齐；用 `--dry-run` 复核 |
| 3 | `auth` | 没解析到 apiKey，或在错的 profile | → **blueai-cli-auth**；先 `blueai-cli doctor` |
| 4 | `network` | 超时 / TCP / DNS / 502·503·504 | CLI 已自动重试 2 次；查网络后重试 |
| 1 | `api_error` | 后端业务错（参数被拒、资源不存在、限额、429/4xx/5xx） | 看 `error.message` + `error.detail.body`；对照 spec 修参数 |
| 5 | `internal` | CLI 自身 bug | 罕见；带 `--verbose` 复现上报 |
| 130 | `interrupted` | Ctrl-C / SIGTERM 中断了轮询 | `detail` 含 `task_id`，用 `task status <id> --watch` 续等 |

> 429 / 5xx 的临时抖动 CLI 已带 Retry-After 自动重试，不必手动处理。**401/403 是 `api_error` 不是 exit 3**——key 解析到了但无效/越权，属换 key 问题不是放置问题。

## 异步与任务注册表

很多生成/处理类命令是异步的（`spec list` 里 `async:true`）。两种姿势：

**默认（前台轮询）**：不加 `--async`，CLI 阻塞轮询到终态（succeeded/failed）才返回最终 body。适合「就等这一个结果」。

**`--async`（后台 fire-and-forget）**：立即返回 `task_id` 并写入 `~/.blueai/tasks.json`。适合 agent 先发一批、去干别的、回头一次性收口：

```bash
blueai-cli task list [--status pending] [--service kling]   # 看挂着哪些任务
blueai-cli task status <task_id> --watch                    # 盯单个到终态（自动从注册表读轮询配置）
blueai-cli task wait --ids '["abc","def"]' --format ndjson  # 等指定几个
blueai-cli task wait --all --format ndjson                  # 等所有 pending（agent 最爱：无需记 id）
```

> 注册表跨会话持久：上个会话 `--async` 提交的任务，这个会话 `task wait --all` 仍能收到。终态条目 7 天后自动清理。

## 批量模式（一次调用跑 N 个）

`--params` 传 **JSON 数组**即批量并发：

```bash
blueai-cli aigc image text2image jimeng \
  --params '[{"_label":"a","prompt":"猫"},{"_label":"b","prompt":"狗"}]' \
  --concurrency 3 --format ndjson
```

- 每项可带保留键：`_label`（回显对账，调用前剥离）、`_file`（逐项文件，multipart 命令用，不能和全局 `--file` 混用）。
- **`--format ndjson` 是 agent 首选**：每行一个结果 `{"index":0,"label":"a","ok":true,"data":{...}}`，末行 `{"batch_summary":{"total":N,"succeeded":S,"failed":F}}`；进度走 stderr `{"_progress":{...}}`。
- `--concurrency N`（默认 3）控并发；`--fail-fast` 首个失败后停止调度新项。
- **agent 终极姿势**：批量 + `--async` 先全发出去 → 回头 `task wait --all --format ndjson` 收齐。

## 通用 flag 速查（所有动态命令）

| flag | 作用 |
|---|---|
| `--params '<JSON>'` | 业务参数；对象=单次，数组=批量 |
| `--async` | 立即返回 task_id，写入注册表，不阻塞 |
| `--dry-run` | 只打印将发出的 HTTP body，不真调——排参数最快 |
| `--format json\|ndjson\|table\|csv` | 默认 json；批量/收口用 ndjson |
| `--file <相对路径>` | multipart 命令上传本地文件（路径穿越保护） |
| `--api-key <key>` | 单次覆盖凭证（最高优先级，不落盘） |
| `--concurrency N` / `--fail-fast` | 仅批量模式 |
| `--verbose` | 打印请求/重试细节到 stderr |
| `--timeout <秒>` | 覆盖本次请求超时（默认 30s） |

## 首次/排错三板斧

```bash
blueai-cli doctor          # 体检：config / 工作区凭证 / apiKey 来源 / gateway 连通
blueai-cli config init     # 没 key 就配（交互）；CI/agent 用 --api-key "$KEY" 避免 stdin 阻塞
blueai-cli spec list       # 不带过滤=列全部命令，确认某能力到底存不存在
```

## 分发：识别意图后路由到领域 skill

本 skill 是入口和底座；**具体领域的选型、前置链路、参数选择交给领域 skill**（它们假设你已懂上面的契约）。按意图下钻：

| 用户意图 | 路由到 |
|---|---|
| 文生图/图生视频/数字人/TTS/声音克隆/音乐/ASR——「生成」类 | **blueai-cli-aigc** |
| 抓小红书/抖音/B站/微博帖子、公众号文章、视频号 | **blueai-cli-social-data** |
| 网盘转存、公网链接抓取入云存储、上传本地文件、分享/打包链接、媒体检索 | **blueai-cli-media-storage** |
| 视频去字幕/去水印/超分/切片/分镜/合成/混剪 | **blueai-cli-video-tools** |
| LLM 批量打标/情感分析/分类/实体抽取/视觉分析（表格数据规模化） | **blueai-cli-datahub** |
| 配 key、鉴权过不去、exit 3、profile 切换、迁移旧凭证 | **blueai-cli-auth** |
| 都不匹配（冷门命令 / 新服务 / 一次性调用） | 留在本 skill，走黄金回路：`spec list` → `schema` → `--dry-run` → call |

> 领域 skill 有就用它（更专、含选型与坑），但任何时候命令调不通、输出读不懂、异步收不回，都回到本 skill 的通用契约。

## 常见错误

| 错误 | 修正 |
|---|---|
| 凭记忆写命令路径，路径不存在 | 先 `spec list --path '<glob>'` 确认 paths[] |
| 调用时把路径写成点分（`jimeng.v4`）→ Unknown command | 调用用空格分段（`jimeng v4`）；点分只喂给 `schema`/`spec` 查询 |
| `schema`/`spec` 用空格分段 → not_found | 查询命令要传完整点分路径当一个参数 |
| 凭记忆写 model_id/参数名 | `schema <path> --resolve-refs` 读 requestBody 段 |
| 只看 `bodyParams` 没加 `--resolve-refs` | 看到的是 `$ref` 占位，约束/enum 在 resolve 后的 requestBody |
| 直接花真调用试参数 | 先 `--dry-run` 看 body，对了再去掉 |
| 从 `.data.task_id` 取值取不到 | 直接调用多在双层 `.data.data.task_id`（分服务，以 responseBody 为准）；从 `task wait` 收则是 `.id` / `.result.…` |
| 异步任务还在 processing 就抓产物 | 默认前台轮询已保证终态；`--async` 模式用 `task wait` |
| exit 3 当成业务错去改参数 | exit 3=凭证问题，走 blueai-cli-auth + `doctor` |
| 401/403 当成 exit 3 改 profile | 401/403 是 `api_error`，key 无效/越权，换 key |
| 大批量逐条同步等 | 批量 `--params` 数组 + `--async` + `task wait --all` |

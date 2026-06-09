---
name: blueai-cli-social-data
description: 通过 blueai-cli 的 data social.* 命令族采集社媒数据：小红书/抖音/B站/微博等平台的存量帖子和评论；微信公众号的发文列表、文章详情、关键词搜索、文章评论；微信视频号的账号搜索、视频列表、视频评论、搜一搜搜视频、视频下载链接，共 10 种采集场景。当用户说"获取社媒数据"、"抓取小红书/抖音/B站/微博数据"、"采集帖子"、"获取公众号文章"、"抓取微信公众号"、"获取文章详情/正文"、"搜索微信文章"、"关键词搜索公众号"、"获取文章评论"、"搜索视频号"、"获取视频号视频"、"视频号评论"、"搜一搜视频"、"获取视频下载链接"、"social media data"等关键词时，必须使用本 skill。即使用户只说"帮我抓几个帖子"、"看看某公众号最近发了什么"、"搜一下视频号"等模糊描述，也应立即启动本 skill。本 skill 是 blueai-cli 之上的对话编排层 —— 把用户的自然语言意图翻译成正确的 CLI 调用，凭证、轮询、超时、批量并发都由 CLI 负责。
---

> **用户使用说明**：本 skill 目录下的 `README.md` 包含安装前置、凭证配置和命令速查。

# 社媒数据采集（基于 blueai-cli）

## 核心理念

本 skill 是 **blueai-cli 之上的薄编排层**：

- 不再调用 Python 脚本、不再维护 venv，**所有 HTTP 请求由 `blueai-cli data social.*` 子命令完成**
- 凭证、轮询、重试、批量并发、任务注册表均由 CLI 提供，本 skill 只负责"把用户意图翻译成正确的 CLI 命令"
- 输出为标准 JSON envelope（`{ok, data, meta}`），归档到本地后再渲染 markdown 摘要

## 10 种采集场景 → CLI 命令对照

| 场景标签（用户语言） | 触发关键词 | CLI 命令路径 |
|---|---|---|
| **存量帖子搜索** | 小红书/抖音/B站/微博 + 关键词 + 时间范围 | `blueai-cli data social batch task` |
| **公众号发文列表** | "公众号最近发了什么" / "获取人民日报的文章" | `blueai-cli data social wp post-list` |
| **公众号文章详情** | "获取这篇文章的正文" / 提供 mp.weixin.qq.com 链接 | `blueai-cli data social wp post-detail` |
| **公众号关键词搜索** | "搜索公众号文章" / "微信上关于X的文章" | `blueai-cli data social wp post-kw-search` |
| **公众号文章评论** | "这篇公众号的评论" / 提供文章链接要评论 | `blueai-cli data social wp post-comment` |
| **视频号账号搜索** | "搜索视频号" / "找视频号账号" | `blueai-cli data social wx video-account-kw-search` |
| **视频号视频列表** | "央视新闻的视频号视频" / "获取视频列表" | `blueai-cli data social wx video-list` |
| **视频号视频评论** | "这个视频的评论" + 提供 video_id | `blueai-cli data social wx video-comment` |
| **搜一搜搜视频** | "微信搜一搜" / "搜索视频内容" | `blueai-cli data social wx web-search-videos` |
| **视频下载链接** | "下载视频" / "视频下载地址" + 提供 video_id | `blueai-cli data social wx video-download-url` |

> 完整字段映射（每个命令的必填/选填参数）见 `references/modes.json`。**首次进入 Step 2 必须读取该文件**。

## 数据获取的两阶段流程

CLI 现在为这 10 个 create 操作配置了原生 async 轮询（status: 0/1/2/3 → pending/processing/succeeded/failed），但 smcrawler API 的特点是 **状态查询只返回 status，实际数据需要再调一次 fetch-data**。所以完整流程是：

```
1. 提交任务 → CLI 自动轮询到 status=2 → 返回 {data: {task: {task_id, status, create_time}}}
2. 拿 task_id 再调 `data social task fetch-data` → 返回真正的帖子/文章/评论数据
3. JSON 写入 BASE_DIR/output/<task_id>.json，渲染 markdown 摘要
```

---

## 路径约定

- **BASE_DIR** = `~/.claude/blueai-runtime/blueai-cli-social-data/`（运行时数据根目录，可由 `--base-dir` 覆盖）
- 输出目录：`BASE_DIR/output/<mode_key>/<task_id>.json`

---

## Workflow

### Step 0：调用模式检测

```
消息中是否包含 "_skill_call": "blueai-cli-social-data" 的 JSON 块？
  ├─ 是 → 结构化模式，跳至 [结构化快速路径]
  └─ 否 → 交互模式，继续 Step 1
```

---

## 结构化快速路径（Structured Mode）

被其他 skill 调用时走此路径，**全程静默**，无任何交互提示。

### S1：解析输入

调用方传入 JSON：
```json
{
  "_skill_call": "blueai-cli-social-data",
  "mode": "stock | realtime_wp | realtime_wp_detail | realtime_wp_kw_search | realtime_wp_comment | realtime_wx_channels_kw_search | realtime_wx_channels_video_list | realtime_wx_channels_video_comment | realtime_wx_channels_video_search | realtime_wx_channels_video_download",
  "params": { /* CLI 原始 JSON 参数 */ },
  "options": {
    "api_key": "可选，覆盖 BLUEAI_API_KEY",
    "format": "json | csv（默认 json）"
  }
}
```

读取 `references/modes.json` 找到 mode 对应的 `cli_path` 和 `requires_fetch_data` 标志。

### S2：执行命令

```bash
# 1) 提交并自动轮询直到 status=succeeded
blueai-cli data social <cli_path> --params '<params_json>' --format json > /tmp/create.json

# 2) 提取 task_id
TASK_ID=$(jq -r '.data.task.task_id // .data.task_id' /tmp/create.json)

# 3) 拉取实际数据
blueai-cli data social task fetch-data --params "{\"task_id\":\"$TASK_ID\"}" --format json \
  > "$BASE_DIR/output/<mode>/$TASK_ID.json"
```

### S3：输出结构化结果

```json
{
  "_skill_result": "blueai-cli-social-data",
  "status": "success",
  "mode": "stock",
  "task_id": "task_abc123",
  "cli_path": "data social batch task",
  "output_file": "/absolute/path/to/<task_id>.json",
  "total_cnt": 2341,
  "error": null
}
```

失败时 `status: "error"`，`error` 字段写错误信息，其余字段可为 null。

---

## 交互模式（Interactive Mode）

### Step 1：意图识别

读取 `references/modes.json`，按用户消息中的关键词匹配到一种 mode：

| 用户语言中含有 | 直接选 |
|---|---|
| 小红书/抖音/B站/微博 + 关键词 | `stock` |
| 公众号 + 名称（如"人民日报"） | `realtime_wp` |
| `mp.weixin.qq.com/s/` 链接 + 评论 | `realtime_wp_comment` |
| `mp.weixin.qq.com/s/` 链接 + 详情/正文 | `realtime_wp_detail` |
| 公众号 + 关键词搜索 | `realtime_wp_kw_search` |
| 视频号 + 账号搜索 | `realtime_wx_channels_kw_search` |
| 视频号 + 名称（如"央视新闻"） | `realtime_wx_channels_video_list` |
| 视频号 + video_id + 评论 | `realtime_wx_channels_video_comment` |
| 搜一搜 + 搜视频 | `realtime_wx_channels_video_search` |
| video_id + 下载 | `realtime_wx_channels_video_download` |

意图模糊时，向用户列出 2~3 个候选 mode 的标签让用户挑选。

### Step 2：参数收集与确认

**必须按以下顺序：**

1. **读取 `references/modes.json`**，找到当前 mode 的 `params` 块（含 required/optional 字段、字段类型、aliases）
2. **读取 `references/input_conversion.md`**，按其中的转换规则把用户的中文/自然语言转成 API 原始值
3. 渲染参数确认表，**只展示`参数 | 值`两列**，使用用户可读的标签：

```
**参数确认 — {mode 中文标签}**

| 参数 | 值 |
|------|-----|
| 平台 | 小红书 |
| 关键词 | 防晒霜 |
| 开始日期 | 2026-01-01 |
| 结束日期 | 2026-03-31 |
| 数据范围 | 仅帖子 |
| 互动量下限 | 1000 |
| 排序 | 互动量 降序 |

执行命令预览：
  blueai-cli data social batch task --params '{"keywords":"防晒霜","media_id":4,"start_time":1767196800,"end_time":1774972799,"data_type":0,"min_interact_cnt":1000,"sort":{"field":"interaction_cnt","order":"DESC"}}' --format json

确认无误请回复 Y。
```

> 用户回复 debug 或要求"看 API 值"时，额外展示一列 `API 值`。
> 不确定的字段在"值"列用 `⚠️ 请核对` 标注。

### Step 3：执行

确认后按以下步骤执行（**全部通过 Bash 工具调用 blueai-cli**）：

```bash
# 0. 凭证检查（一次性）
#    - 优先 --api-key 显式传入
#    - 其次工程级 .blueai/credentials.json（沿 CWD 向上查找）
#    - 再次 BLUEAI_API_KEY 环境变量
#    - 兜底 ~/.blueai/credentials.json（由 `blueai-cli config init` 写入）
#    若用户未配置，提示运行 `blueai-cli config init` 后再回到本 skill。

# 1. 准备目录
BASE_DIR="$HOME/.claude/blueai-runtime/blueai-cli-social-data"
MODE="<mode_key>"   # 如 stock / realtime_wp / ...
mkdir -p "$BASE_DIR/output/$MODE"

# 2. 提交并自动轮询（CLI 内部已配置 statusPath=/api/task/getStatus, normalizeStatus=smcrawler）
blueai-cli data social <cli_path> \
  --params '<params_json>' \
  --format json \
  > "$BASE_DIR/output/$MODE/_create_$$.json"

# 3. 提取 task_id（兼容 data.task.task_id 嵌套结构）
TASK_ID=$(jq -r '.data.data.task.task_id // .data.task.task_id // .data.task_id' \
  "$BASE_DIR/output/$MODE/_create_$$.json")

# 4. 拉取实际数据（fetch-data 是 GET 接口，可重复调用，分页用 scroll_id+limit）
OUTPUT="$BASE_DIR/output/$MODE/$TASK_ID.json"
blueai-cli data social task fetch-data \
  --params "{\"task_id\":\"$TASK_ID\",\"limit\":500}" \
  --format json > "$OUTPUT"
```

**关键点：**
- 不再使用 `--async`：**默认就是同步等待**（CLI 内置 async 轮询，会阻塞到 status=2/3）
- 用户要"先返回 task_id 后台跑"时，加 `--async`，CLI 立刻返回；后续用 `blueai-cli task wait --ids '["task_xxx"]'` 或 `blueai-cli task status task_xxx --watch` 阻塞等待
- 任务自动写入 `~/.blueai/tasks.json`，`blueai-cli task list` 可查
- fetch-data 单次最多 500 条，超过用 `scroll_id` 翻页（`fetch-data` 响应里有 `data.scroll_id`）

### Step 4：渲染结果摘要

从 `$OUTPUT` 解析以下字段（不同 mode 字段名有差异，按需取）：

```
**采集完成 — {mode 中文标签}**

| 字段 | 值 |
|------|-----|
| 任务 ID | {task_id} |
| 数据条数 | {data 数组长度，或 total_cnt 字段} |
| 输出文件 | {绝对路径，必须完整展示，不得省略或截断} |
| 创建时间 | {create_time 格式化为 yyyy-MM-dd HH:mm:ss} |
| 命令 | blueai-cli data social {cli_path} |

数据预览（前 3 条）：
  1. {标题或正文前80字} — {作者/公众号}
  2. ...

需要下一页 / CSV 导出 / 字段筛选请告知。
```

**展示原则：**
- 文件路径、task_id 等长字段必须完整展示，**严禁截断或用 `...` 省略**
- 多平台并行任务（一次提交多个）时，每个平台单独渲染表格 + 总计汇总表

---

## 内置便捷命令

| 用户说的话 | 实际执行 |
|---|---|
| "查询任务 task_xxx" | `blueai-cli task status task_xxx --watch` |
| "列出任务" | `blueai-cli task list` |
| "等所有任务" | `blueai-cli task wait --all --format ndjson` |
| "用 CSV 格式" | 在最近一次命令里把 `--format json` 改成 `--format csv` |
| "重新拉数据" | 用相同 `task_id` 再调一次 `data social task fetch-data` |

---

## 批量调用（一次提交多个）

CLI 原生支持批量：`--params` 传 JSON 数组，每个对象一个任务，自动并发。

```bash
blueai-cli data social batch task --params '[
  {"keywords":"防晒霜","media_id":4,"start_time":1767196800,"end_time":1774972799,"_label":"xhs-fangshai"},
  {"keywords":"防晒霜","media_id":5,"start_time":1767196800,"end_time":1774972799,"_label":"dy-fangshai"}
]' --concurrency 3 --format ndjson --async
```

`--async` + NDJSON 是 agent 工作流的推荐组合：每个 task 提交后立即返回 task_id，agent 可以继续干其他活；最后 `blueai-cli task wait --all` 收集结果。

---

## 错误处理

| 错误 | 处理 |
|---|---|
| 退出码 3（auth error，提示 apiKey 未配置） | 引导用户运行 `blueai-cli config init`，配置完成后重试 |
| 退出码 4（network error，超时/连接失败） | 提示检查网络，CLI 已自动重试 2 次仍失败时再人工干预 |
| 退出码 1（api_error，业务错误） | 解析响应中的 `error.detail` 字段，定位是参数校验失败、限额耗尽还是任务失败（status=3） |
| 任务 status=3（运行失败） | CLI 抛出带 `detail` 的 BlueAIError，展示 API 返回的失败原因，询问是否同参数重试 |
| 任务超时（默认 5 分钟） | CLI 抛出 timeout，可改用 `--async` 提交后用 `task wait` 等待更长时间 |

---

## 可扩展

| 扩展点 | 操作 |
|---|---|
| 新增 mode | 在 `references/modes.json` 追加一项；如对应 CLI 命令暂未配置 async，需先在 `openapi/smcrawler.yaml` 加 `x-cli.async` 块并 `npm run build` |
| 新增字段转换 | 在 `references/input_conversion.md` 追加映射表，Step 2 自动生效 |
| 修改输出归档路径 | 改 SKILL.md Step 3 中的 `BASE_DIR` 拼接逻辑 |
| 切换 API 地址 | `blueai-cli` 通过 `BLUEAI_SMCRAWLER_GATEWAY` 环境变量覆盖（spec 默认值在 `openapi/smcrawler.yaml` 的 `servers[0].url`） |

---

## Data Storage

```
~/.claude/blueai-runtime/blueai-cli-social-data/
└── output/
    ├── stock/<task_id>.json
    ├── realtime_wp/<task_id>.json
    └── ...
```

凭证/任务注册表由 CLI 维护，**不在本 skill 的数据目录下**：
- 凭证：`~/.blueai/credentials.json`（由 `blueai-cli config init` 管理）
- 任务注册表：`~/.blueai/tasks.json`（CLI 提交 `--async` 任务时自动写入，7 天自动清理终态）

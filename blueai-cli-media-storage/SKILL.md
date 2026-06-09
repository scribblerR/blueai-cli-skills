---
name: blueai-cli-media-storage
description: >
  使用 blueai-cli 的 media-storage 命令族操作 BLUEAI 媒体存储服务（上传 / 分享 / 媒体查询 / 场景检索 / 打包 / 本地文件流式上传）。
  当用户需要：从百度网盘转存视频、从公网链接抓取媒体到云存储（COS/OSS/TOS/BOS/GCP）、
  上传本地文件到对象存储、生成分享链接或下载短链、按 task_id/media_id 查询媒体详情、
  按时间范围或场景批量检索媒体/任务、打包多媒体生成 zip 下载链接 —— 任何此类操作都必须使用本技能。
  即使用户没有显式说"blueai-cli"或"媒体存储"，只要意图涉及百度网盘转存、视频下载留存、对象存储上传、
  云存储链接外发、媒体批量处理，也应优先使用本技能而不是手写 curl/requests。
---

# BlueAI Media Storage（CLI 版）

通过 `blueai-cli` 调用 BlueAI Media Storage OpenAPI。HTTP / 鉴权 / 重试 / multipart / 批量并发都由 CLI 内置处理 —— 本技能只负责教 Agent 如何选子命令、如何拼 `--params`、如何解读响应。

## 前置条件

1. **已安装 `blueai-cli`** —— 验证：`blueai-cli --version`
2. **已配置 API Key**（任选其一，按优先级）：
   - `--api-key <key>` 命令行参数
   - 工程级 `./.blueai/credentials.json`（沿 CWD 向上查找）
   - `BLUEAI_API_KEY=<key>` 环境变量
   - 用户级 `~/.blueai/credentials.json`（首次用 `blueai-cli config init`）

如果命令返回 `{"ok": false, "error": {"type": "auth", ...}}` 即认证缺失。

## 命令族总览

```
blueai-cli media-storage
├── upload create         # 创建上传任务（百度盘/公网URL/内部OS → 云存储）
├── upload result         # 查询上传任务结果（含分页）
├── share create          # 创建分享任务（生成百度网盘分享链接）
├── share result          # 查询分享任务结果
├── package create        # 创建打包任务（多媒体合并为 zip）
├── package result        # 查询打包任务结果
├── media info            # 批量查询媒体详情（按 media_id）
├── scene media-list      # 按场景+时间范围查询媒体
├── scene task-list       # 按场景+时间范围查询任务（含媒体列表）
└── file upload           # 流式上传本地文件到 COS（可异步同步到 GCP/BOS/...）
```

每个子命令的 `--params` 字段、HTTP 方法、响应形状参见 [references/commands.md](references/commands.md)。

## 通用调用范式

每个子命令都接受这套通用 flag：

| Flag | 说明 |
|------|------|
| `--params '<JSON>'` | 业务参数。**单次**传 JSON 对象；**批量**传 JSON 数组（CLI 自动并发执行） |
| `--file <path>` | 仅 `file upload` 使用。**必须是相对路径**（路径穿越保护） |
| `--format json\|ndjson\|table\|csv` | 默认 `json`；批量场景推荐 `ndjson`，每行一个结果便于流式读取 |
| `--dry-run` | 预览将要发出的 HTTP body，不实际调用 —— 排查参数最快的方式 |
| `--verbose` | 打印请求/重试细节 |
| `--api-key <key>` | 临时覆盖 API Key |
| `--concurrency <N>` | 仅批量模式生效（默认 3） |
| `--fail-fast` | 批量模式遇首个失败即停止后续调度 |
| `--async` | 跳过轮询立即返回。本服务全部为 sync 模式，此 flag 通常无效，参见下文异步语义 |

## 响应信封

成功：
```json
{
  "ok": true,
  "data": {                        // ← 这层是后端返回的原始 body
    "code": 0,
    "message": "success",
    "data": { "task_id": "abc" }   // ← 后端业务 payload 在这里
  },
  "meta": { "service": "media-storage", "path": "media-storage.upload.create" }
}
```

失败：
```json
{ "ok": false, "error": { "type": "auth|validation|api|network|internal", "message": "...", "hint": "..." } }
```

读取业务结果时切记**双层 data**：例如任务 ID 在 `.data.data.task_id`，状态在 `.data.data.status`。

## 异步语义（重要）

`upload create` / `share create` / `package create` 在语义上都是**长耗时任务** —— 创建后服务端在后台处理。但本服务在 spec 中全部声明为 `sync: true`，意味着：

- 创建命令**立即返回 `task_id`**，CLI 不会自动轮询
- 必须**手动调用对应的 `result` 命令**直到状态进入终态
- **任务终态**：`COMPLETED` / `FAILED` / `PARTIAL_SUCCESS`
- **媒体终态**：`COMPLETED` / `FAILED`
- 不要使用 `blueai-cli task list` / `task wait` —— 这些只对 spec 中 `sync: false` 的服务生效，本服务任务**不会**写入 `~/.blueai/tasks.json`
- 轮询节奏 3–10 秒一次为宜，不要无间隔死循环；后端会限流

## 典型场景速查

### 1) 百度网盘 → COS

```bash
blueai-cli media-storage upload create --params '{
  "source_type": "BAIDU_PAN",
  "object_list": [{"url":"https://pan.baidu.com/s/1xxx", "vcode":"abc1"}],
  "target_storage": ["COS"]
}'
# 取出 .data.data.task_id，然后：
blueai-cli media-storage upload result --params '{"task_id":"<id>"}'
# 重复调用直到 .data.data.status ∈ {COMPLETED, FAILED, PARTIAL_SUCCESS}
```

### 2) 公网 URL 批量入库（并发）

`--params` 传数组即触发批量；推荐配 `--format ndjson` 流式读结果：
```bash
blueai-cli media-storage upload create --params '[
  {"source_type":"PUBLIC_URL","object_list":[{"url":"https://a.com/1.mp4"}],"target_storage":["COS"],"_label":"v1"},
  {"source_type":"PUBLIC_URL","object_list":[{"url":"https://a.com/2.mp4"}],"target_storage":["COS"],"_label":"v2"}
]' --concurrency 3 --format ndjson
```
`_label` 仅会原样回显在每条结果里供关联，会被 CLI 自动剥离不发给后端。

### 3) 本地文件流式上传

```bash
# --file 必须是相对路径；file_size 必须由调用方计算后写进 --params
cd /path/to/work
SIZE=$(wc -c < ./video.mp4)
blueai-cli media-storage file upload --file ./video.mp4 --params "{\"file_size\":$SIZE}"
```
**重要**：`file_size`（字节数）是后端 query 必填参数，**CLI 不会自动从磁盘补全** —— 调用方必须先 `wc -c` / `stat` 拿到字节数再写入 `--params`。响应里如果带 `task_id` 且任务方会异步转存到 GCP/BOS 等其他存储，则继续用 `upload result` 轮询拿全部链接。

### 4) 创建分享链接

```bash
blueai-cli media-storage share create --params '{
  "task_ids": ["<task1>"],
  "period": 7,
  "remark": "外部分享"
}'
# 取出 .data.data.share_task_id
blueai-cli media-storage share result --params '{"share_task_id":"<id>"}'
# .data.data 中含 short_url（短链）/ link（完整链接）/ pwd（提取码）
```
注意 `task_ids` / `media_ids` / `url_list` 三选一即可，可组合。

### 5) 按场景查询历史

```bash
blueai-cli media-storage scene media-list --params '{
  "scene": ["blueai"],
  "start_time": 1735689600,
  "page_size": 200
}'
```
`start_time` 是 Unix 秒时间戳（必填）；`page_size` 上限 1000；可用 `user_email` / `task_id` 进一步过滤。

更多完整工作流（含错误处理与变体）见 [references/workflows.md](references/workflows.md)。

## 枚举速查

- **source_type**: `BAIDU_PAN | PUBLIC_URL | INTERNAL_OS | LOCAL_FILE`
- **target_storage[]**: `COS | OSS | TOS | BOS | GCP`（**上传任务不支持 `BOS`**）
- **media_type**: `VIDEO | AUDIO | IMAGE | FILE | DOCUMENT | ARCHIVE | FONT | CODE`
- **task_status**: `PENDING | PROCESSING | COMPLETED | FAILED | PARTIAL_SUCCESS | PREPARING | EXPIRED | ALL`
- **media_status**: `PENDING | PROCESSING | COMPLETED | FAILED`
- **scene**: `google | blueai | dify`
- **platform**: `xhs | bilibili | dy | tiktok | youtube`
- **object_acl**: `private | public-read`

完整字段与请求/响应模型见 [references/data-models.md](references/data-models.md)。

## 调试与排错

- **不确定 `--params` 形状** → 先 `--dry-run`，CLI 会打印实际即将发出的 body：

  ```bash
  blueai-cli media-storage upload create --params '{"source_type":"PUBLIC_URL", ...}' --dry-run
  ```
- **想看重试/超时细节** → 加 `--verbose`
- **`error.type == "validation"`** → CLI 在发出请求前就拒绝了，说明 `--params` JSON 字段缺失或类型不对，按 spec 补齐
- **`error.type == "auth"`** → 检查 API Key：`echo $BLUEAI_API_KEY` 或确认凭证文件存在
- **`error.type == "api"`** → 业务错误码（在 `error.detail.body` 里能看到原始响应）：
  | code | 含义 | 处理 |
  |------|------|------|
  | `1003` | API Key 无效 / 已过期 | 重新签发或换 key |
  | `9001` | 请求参数错误 | 对照 spec 排查 `--params` 内容（vs CLI 端 validation） |
  | `2000` | 资源不存在 | task_id / media_id 错误或已过期 |
  | `9099` | 后端 5xx | CLI 已自动重试 2 次仍失败，稍后再试 |
- **`error.type == "network"`** → 30 秒请求超时或 TCP 异常，重试即可

## 边界与限制

- 单个 `upload create` 任务上限 **100 GB**
- 单次 `file upload` multipart 最多 **300 个文件**
- `scene media-list` `page_size ≤ 1000`；`scene task-list` `page_size ≤ 100`
- 上传任务 `target_storage` **不支持 `BOS`**（媒体查询接口可以）
- `file upload --file` 仅接受相对路径；遇到绝对路径请先 `cd` 到合适目录
- 批量 `--params` 数组的每一项可携带 `_label`（关联标签）；`file upload` 批量场景可携带 `_file`（相对路径），但 `_file` 不能与全局 `--file` 同时使用

## 与原有 BLUEAI Media Storage 技能的关系

本技能取代旧版基于 curl/Python `requests` 的调用方式。所有原本走 HTTP 的操作，都已映射到 `blueai-cli media-storage <子命令>`。Agent 不应再自己拼 URL、设 `Authorization` 头、写重试循环 —— 这些 CLI 已统一处理。

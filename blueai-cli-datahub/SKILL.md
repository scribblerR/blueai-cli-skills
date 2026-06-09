---
name: blueai-cli-datahub
description: Use when calling DataHub LLM batch processing through the blueai-cli (`blueai-cli tools ai-batch openapi *`). Trigger this skill whenever users mention 数据标注, AI批量处理, 情感分析, 文本分类, 实体提取, 小红书/抖音/微博/B站数据标注, 飞书多维表格批量打标, LLM批量任务, model-list, 视觉分析, OCR, batch labeling, or want to use AI/LLM to process tabular data (CSV/Excel/JSON) at scale through blueai-cli. Also triggers when user wants to label/analyze data from blueai-social-media-data or blueai-media-storage-skill output. Prefer this skill over the legacy blueai-datahub-skill (which uses Python SDK + raw REST) whenever the user already has blueai-cli installed.
license: MIT
metadata:
  author: BMC Team
  version: "2.0.0"
  domain: cli-integration
  triggers: blueai-cli, ai-batch, openapi, DataHub, LLM任务, 数据处理, 数据标注, AI标注, 批量标注, 情感分析, 文本分类, 视觉分析, 小红书, 抖音, 微博, 飞书多维表格, 模型列表, model-list, 上传文件, upload-file, task-create, task wait
  role: specialist
  scope: implementation
  output-format: shell
  related-skills: blueai-social-media-data, blueai-media-storage-skill
---

# BlueAI DataHub (CLI 版)

通过 `blueai-cli` 调用 DataHub 的 LLM 批处理能力，专注于数据标注、批量打标和多模态分析。

> **何时用这个 skill 而不是 `blueai-datahub-skill`**
> 旧 skill 用 Python SDK + 原生 curl，`DATAHUB_API_KEY` 单独管理。本 skill 直接调 `blueai-cli`，credentials 走统一的 `BLUEAI_API_KEY` / `~/.blueai/credentials.json`，async 和 batch 由 CLI 内置任务注册表处理。**项目里已经装了 blueai-cli 时，优先用本 skill。**

## Quick Start

```bash
# 0. 一次性配置 apiKey（已配过可跳过）
blueai-cli config init        # 交互式写入 ~/.blueai/credentials.json
# 或临时通过环境变量
export BLUEAI_API_KEY="your-api-key"

# 1. 上传数据文件 → 拿 data_source_id（同步，立即返回）
blueai-cli tools ai-batch openapi upload-file \
  --params '{"file_name":"data.csv"}' \
  --file ./data.csv

# 2. 创建任务（默认异步，CLI 自动轮询到终态再返回）
blueai-cli tools ai-batch openapi task-create --params '{
  "data_source": {"data_source_id": "<上一步返回的 data_source_id>"},
  "prompt": {"prompt_text": "分析情感：{{content}}"}
}'
```

> **关键点**：Prompt 中的 `{{content}}` 必须对应数据文件的**列名**。CSV 有 `text` 列就用 `{{text}}`。

## CRITICAL CONSTRAINTS

1. **必须执行真实 CLI 命令** — 任何 task_id、result_url、data_source_id 都来自实际的 `blueai-cli` 调用，禁止伪造。
2. **优先用 `--async` + `task wait`** — 大批量场景立即返回 task_id，agent 可以同时干别的事，最后用 `blueai-cli task wait --all` 一次收齐结果。
3. **不要硬编码 apiKey** — 通过 `blueai-cli config init` 落到 `~/.blueai/credentials.json`，或临时用 `BLUEAI_API_KEY` 环境变量，绝不能写到 prompt/代码里。
4. **解析输出包络** — CLI 输出统一是 `{"ok":true,"data":...}` 或 `{"ok":false,"error":...}`，`data_source_id` 在 `.data.data.data_source_id`，`task_id` 在 `.data.data.task_id`。
5. **URL 展示** — `result_url` 包含签名，永远用 Markdown 链接 `[下载结果](URL)` 完整展示，禁止截断。
6. **失败提示信号** — 退出码 3 = 缺 apiKey；exit 1 + `error.type=api_error` = DataHub 业务错误，看 `error.message`。

## When to Use This Skill

- 创建 LLM 批处理任务（情感分析、分类、实体提取、摘要、视觉分析…）
- 上传 CSV/Excel/JSON 到 DataHub 拿 `data_source_id`
- 查询/挑选适合的模型（`model-list`，按 vision/reasoning 能力筛）
- 跨会话异步批处理：提交完去做别的事，回头 `task wait --all` 收结果
- 与 `blueai-social-media-data` 或 `blueai-media-storage-skill` 串成 "采集/上传 → 标注/视觉分析" 流水线
- 飞书多维表格批量打标 + 结果回写

## 认证与配置

CLI 凭据查找顺序：`--api-key` 标志 → 工作区 `<project>/.blueai/credentials.json` → `BLUEAI_API_KEY` 环境变量 → 用户 `~/.blueai/credentials.json`。

```bash
# 推荐：交互式落到用户配置
blueai-cli config init

# 临时（脚本里用）
export BLUEAI_API_KEY="your-api-key"

# 检查是否能正常请求
blueai-cli doctor
```

> 如果用户的旧配置是 `DATAHUB_API_KEY` 或带 `providers.*` / `services.*` 桶的 credentials，跑 `blueai-cli config migrate` 一次性收敛到统一的 `apiKey`。

## 三个核心命令

| 用途 | 命令 | sync/async |
|---|---|---|
| 上传文件 | `blueai-cli tools ai-batch openapi upload-file --params '{"file_name":"data.csv"}' --file ./data.csv` | sync |
| 创建任务 | `blueai-cli tools ai-batch openapi task-create --params '{...}'` | async（默认轮询到底） |
| 查模型 | `blueai-cli tools ai-batch openapi model-list --params '{"only_vision":true,"vision_type":"image"}'` | sync |

加 `--async` 后 task-create 立即返回 task_id；CLI 把任务信息写进 `~/.blueai/tasks.json`，后续随时用 `blueai-cli task` 子命令处理：

```bash
blueai-cli task list                          # 看待处理任务
blueai-cli task status <task_id> --watch      # 盯单个任务
blueai-cli task wait --ids '[123,456]'        # 等指定几个任务
blueai-cli task wait --all                    # 等所有 pending 任务
```

## Prompt 占位符语法

`{{变量名}}` 中的变量名必须与数据文件的**列名完全一致**，区分大小写，不允许空格。

```
data.csv 列：id, content
Prompt: "请分析：{{content}}"   ← 跟 content 列名一字不差
```

支持多变量：`"标题：{{title}}，正文：{{content}}，请分析…"`

视觉任务（`PROMPT_TYPE_VISION`）的 prompt **不需要**写 `{{img_url}}` 占位符——通过 `prompt_run_config.vision_fields_names` 声明哪一列是图片 URL，系统会自动取图传给视觉模型。

## 常用 Prompt 模板（snippet）

下面这些 JSON 片段直接拼进 `task-create --params` 的 `prompt` 字段。

**情感分析**
```json
{"prompt_text": "分析以下文本的情感倾向：{{content}}\n\n返回 JSON：{\"sentiment\": \"正面/负面/中性\", \"confidence\": 0.9, \"reason\": \"判断依据\"}"}
```

**文本分类**
```json
{"prompt_text": "将以下文本分类：{{text}}\n\n类别：产品咨询、售后问题、投诉建议、其他\n\n返回 JSON：{\"category\": \"\", \"confidence\": 0.9}"}
```

**实体提取**
```json
{"prompt_text": "从以下文本提取实体：{{content}}\n\n返回 JSON：{\"persons\": [], \"locations\": [], \"organizations\": [], \"dates\": [], \"amounts\": []}"}
```

**视觉分析（图片列名为 `img_url`）**
```json
{
  "prompt_type": "PROMPT_TYPE_VISION",
  "prompt_text": "分析这张图片，标题：{{title}}\n\n返回 JSON：{\"description\": \"\", \"objects\": [], \"scene\": \"\"}",
  "prompt_run_config": {"vision_fields_names": ["img_url"]}
}
```

更多模板见 `references/data-labeling.md`。

## 异步批量工作流（CLI 杀手锏）

当任务多且耗时时，**先全部 fire-and-forget，再统一收结果**——这是 agent 工作流最高效的姿势：

```bash
# 1. 多个任务用 --async 提交（立即返回，自动写进任务注册表）
blueai-cli tools ai-batch openapi task-create --async --params '{
  "data_source":{"data_source_id":"ds-1"},
  "prompt":{"prompt_text":"分析情感：{{content}}"}
}'

blueai-cli tools ai-batch openapi task-create --async --params '{
  "data_source":{"data_source_id":"ds-2"},
  "prompt":{"prompt_text":"提取关键词：{{content}}"}
}'

# 2. agent 去干别的事…

# 3. 回头一次性等所有 pending 任务（NDJSON 流，每完成一个输出一行）
blueai-cli task wait --all --format ndjson
```

**批量同一类任务**（一次 N 条，`--params` 传 JSON 数组）：

```bash
blueai-cli tools ai-batch openapi task-create \
  --concurrency 5 --format ndjson --async \
  --params '[
    {"_label":"v1","data_source":{"data_source_id":"ds-1"},"prompt":{"prompt_text":"分析：{{content}}"}},
    {"_label":"v2","data_source":{"data_source_id":"ds-2"},"prompt":{"prompt_text":"分析：{{content}}"}}
  ]'
```

`_label` 会回显在结果里方便 agent 关联，`--concurrency` 控并发，`--fail-fast` 出错即停。

## 输出包络解析

CLI 的所有输出都是 `{"ok":true,"data":...,"meta":...}` 或 `{"ok":false,"error":{"type":"...","message":"...","hint":"..."}}`。**常用字段路径**：

| 想要的值 | 路径（jq） |
|---|---|
| 上传后的 data_source_id | `.data.data.data_source_id` |
| 创建任务返回的 task_id | `.data.data.task_id` |
| 任务终态里的下载链接 | `.data.data.result_url` |
| 任务终态状态 | `.data.data.task_status`（`TASK_STATUS_GENERATED_RESULT` 或 `TASK_STATUS_SUCCESS` 即完成） |
| 错误类型 | `.error.type`（`api_error` / `validation` / `auth` / `network` / `internal`） |

```bash
# 一行流：上传 + 拿 data_source_id
DS_ID=$(blueai-cli tools ai-batch openapi upload-file \
  --params '{"file_name":"data.csv"}' --file ./data.csv \
  | jq -r '.data.data.data_source_id')

# 创建任务并提取 task_id（异步）
TASK_ID=$(blueai-cli tools ai-batch openapi task-create --async \
  --params "{\"data_source\":{\"data_source_id\":\"$DS_ID\"},\"prompt\":{\"prompt_text\":\"分析：{{content}}\"}}" \
  | jq -r '.data.data.task_id')

# 等任务完成
blueai-cli task wait --ids "[$TASK_ID]" | jq -r '.data.data.result_url'
```

## 与社媒数据 Skill 集成

`blueai-social-media-data` 输出形如：
```json
{"_skill_result":"blueai-social-media-data","status":"success","output_file":"/path/to/task_xxx.xlsx"}
```

**触发**：用户说"对刚才的数据进行情感分析"、"分析这些帖子" → 自动从上下文取 `output_file` 走"上传 → 创建任务"。

社媒 Excel 分两个 sheet：

| Sheet | 常用列 | 占位符 |
|---|---|---|
| `posts` | `post_title`, `post_content`, `post_cover_url`, `post_pic_urls`, `author_user_name`, `post_like_cnt` | `{{post_title}}`、`{{post_content}}`… |
| `comments` | `content`, `like_cnt`, `post_id` | `{{content}}`、`{{like_cnt}}` |

通过 `data_source.local_file_run_config.sheet_name` 指定要分析哪个 sheet：

```bash
blueai-cli tools ai-batch openapi task-create --params '{
  "data_source": {
    "data_source_id": "ds-xxx",
    "local_file_run_config": {"sheet_name": "posts"}
  },
  "prompt": {
    "prompt_text": "分析帖子情感：\n标题：{{post_title}}\n正文：{{post_content}}\n返回 JSON：{\"sentiment\":\"\"}"
  }
}'
```

## 与 Media Storage Skill 集成

`blueai-media-storage-skill` 上传后输出包含 `file_url` / `gcp_url` 的结构。

**单文件视觉分析**（直接用 `data_source_text`，不用上传 CSV）：
```bash
blueai-cli tools ai-batch openapi task-create --params '{
  "data_source": {"data_source_text": [{"url": "https://cdn.../video.mp4"}]},
  "prompt": {
    "prompt_type": "PROMPT_TYPE_VISION",
    "prompt_text": "分析视频，返回 JSON：{\"description\":\"\",\"tags\":[]}",
    "prompt_run_config": {"vision_fields_names": ["url"]}
  },
  "model": {"model_id": "gpt-4o"}
}'
```

**多文件批量分析**：先用 `scripts/media_to_csv.sh` 把多文件输出转成 CSV，再 `upload-file` + `task-create`。

### Gemini 模型自动适配

Gemini 系列要的是 `gs://` 链接（`gcp_url`），不是 `https://`（`url`）。所以视觉任务用 Gemini 时：
- `vision_fields_names` 要写 `["gcp_url"]`，不是 `["url"]`
- prompt 文本里如果原本写 `{{url}}` 也要改成 `{{gcp_url}}`
- 数据源里必须同时有这俩列（Media Storage 用 `--output-format datahub` 会自动输出两列）

模型识别：以 `gemini-` 开头的都按 Gemini 处理。详见 `references/models.md`。

## 同步 vs 异步选择

| 场景 | 推荐 | 命令 |
|---|---|---|
| 数据量小（<100 条），需要立即看结果 | 默认（CLI 自动轮询） | `task-create --params '...'` |
| 数据量大或多任务并发 | 异步 + 后续收单 | `task-create --async ...` 然后 `task wait --all` |
| 单任务但想观察进度 | 异步 + watch | `task-create --async ...` 然后 `task status <id> --watch` |

异步模式下，`~/.blueai/tasks.json` 里的条目即使关掉终端也保留，下次会话能继续 `task list` 看见。

## Reference Guide

| 主题 | 文件 | 何时读 |
|---|---|---|
| Prompt 模板大全（情感/分类/实体/摘要/视觉） | `references/data-labeling.md` | 设计 prompt 时 |
| 数据源四种配置（本地文件/采集/数据库/飞书表格/text） | `references/data-sources.md` | 选数据源类型或配 BI 回写时 |
| 模型列表与 URL 类型选择 | `references/models.md` | 挑模型，特别是视觉/Gemini 时 |
| 错误码与排查 | `references/error-handling.md` | 遇到非 0 退出码或 `error.type` 时 |
| 端到端 bash 示例 | `examples/sentiment_analysis.sh`, `examples/vision_analysis.sh`, `examples/batch_async_workflow.sh` | 复制改改就能用 |
| 多文件 → CSV 工具 | `scripts/media_to_csv.sh` | 把 Media Storage 多文件输出转成 DataHub 数据源 |

## Constraints

### MUST DO
- 创建任务前必须先有 `data_source_id`（除非用 `data_source_text` 或 `data_source_url`）
- 上传文件仅支持 `.csv` / `.xlsx` / `.xls` / `.json`
- Prompt 至少包含一个 `{{列名}}` 占位符（视觉任务的 prompt 文本除外）
- 视觉任务必须设 `prompt_type: PROMPT_TYPE_VISION` **且** 提供 `vision_fields_names`
- 用 `model-list --params '{"only_vision":true}'` 查模型，不要凭印象写 model_id

### MUST NOT DO
- 不要在 `data_source` 里同时塞 `data_source_id`、`data_source_url`、`data_source_text`，三选一
- 不要把 apiKey 写进 `--params` 或脚本字面量
- 不要在任务还在 `RUNNING` 时去抓 `result_url`（先等到 `TASK_STATUS_GENERATED_RESULT` 或 `TASK_STATUS_SUCCESS`）
- 不要给 Gemini 模型传 `https://` URL，要 `gs://`

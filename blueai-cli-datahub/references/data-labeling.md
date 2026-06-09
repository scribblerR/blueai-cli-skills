# 数据标注场景指南（CLI 版）

通过 `blueai-cli` 调 DataHub 做 LLM 批量数据标注。

## 完整工作流

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   上传文件   │ -> │   创建任务   │ -> │   等待完成   │ -> │   下载结果   │
│ upload-file │    │ task-create │    │  task wait  │    │ result_url  │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

四步对应的 CLI 命令：

1. **上传文件** — `blueai-cli tools ai-batch openapi upload-file --params '{"file_name":"..."}' --file ./...`
2. **创建任务** — `blueai-cli tools ai-batch openapi task-create --params '{...}'`（默认轮询到底）
3. **等待完成** — 默认就在等；用 `--async` + `blueai-cli task wait --ids '[id]'` 拆开
4. **下载结果** — 从 `.data.data.result_url` 拿到带签名的下载链接

## 端到端 Bash 示例

```bash
#!/usr/bin/env bash
set -euo pipefail

FILE="评论数据.xlsx"
PROMPT='分析以下评论的情感倾向。\n评论：{{content}}\n返回 JSON：{"sentiment":"正面/负面/中性","confidence":0.0-1.0,"reason":""}'
MODEL="gpt-4o-mini"

# 1. 上传
echo "[1/3] 上传 $FILE"
DS_ID=$(blueai-cli tools ai-batch openapi upload-file \
  --params "{\"file_name\":\"$(basename "$FILE")\"}" \
  --file "$FILE" \
  | jq -r '.data.data.data_source_id')
echo "    data_source_id=$DS_ID"

# 2. 创建任务（同步，CLI 自动轮询到终态返回）
echo "[2/3] 创建任务"
RESULT=$(blueai-cli tools ai-batch openapi task-create --params "$(jq -n \
  --arg ds "$DS_ID" --arg prompt "$PROMPT" --arg model "$MODEL" \
  '{name:"数据标注", data_source:{data_source_id:$ds},
    prompt:{prompt_text:$prompt, prompt_run_config:{require_llm_result_json:true}},
    model:{model_id:$model}}')")

# 3. 提取结果
RESULT_URL=$(echo "$RESULT" | jq -r '.data.data.result_url')
TOTAL=$(echo "$RESULT" | jq -r '.data.data.total_count')
TOKENS=$(echo "$RESULT" | jq -r '.data.data.total_tokens')

echo "[3/3] 任务完成"
echo "  下载：$RESULT_URL"
echo "  条数：$TOTAL，消耗 tokens：$TOKENS"
```

> 用 `jq -n` 拼 JSON 比 heredoc/字符串拼接更安全 — 自动处理引号转义。

## 标注 Prompt 模板

下面这些 JSON 片段直接拼进 `task-create --params` 的 `prompt` 字段。

### 情感分析
```json
{
  "prompt_text": "分析以下文本的情感倾向。\n\n文本内容：{{content}}\n\n返回 JSON：{\"sentiment\":\"正面/负面/中性\",\"confidence\":0.0-1.0,\"reason\":\"\"}",
  "prompt_run_config": {"require_llm_result_json": true}
}
```

### 文本分类
```json
{
  "prompt_text": "将以下文本分类：{{text}}\n\n类别：产品咨询、售后问题、投诉建议、其他\n\n返回 JSON：{\"category\":\"\",\"confidence\":0.0-1.0}",
  "prompt_run_config": {"require_llm_result_json": true}
}
```

### 实体提取
```json
{
  "prompt_text": "从文本提取实体：{{content}}\n\n类型：人名、地点、组织、日期、金额\n\n返回 JSON：{\"persons\":[],\"locations\":[],\"organizations\":[],\"dates\":[],\"amounts\":[]}",
  "prompt_run_config": {"require_llm_result_json": true}
}
```

### 关键词 + 摘要
```json
{
  "prompt_text": "提取关键词并生成摘要：{{content}}\n\n返回 JSON：{\"keywords\":[],\"summary\":\"一句话摘要\"}",
  "prompt_run_config": {"require_llm_result_json": true}
}
```

### 质量评估
```json
{
  "prompt_text": "从准确性、完整性、可读性、专业性四个维度评分（1-10）：{{content}}\n\n返回 JSON：{\"accuracy\":0,\"completeness\":0,\"readability\":0,\"professionalism\":0,\"overall\":0,\"feedback\":\"\"}",
  "prompt_run_config": {"require_llm_result_json": true}
}
```

## 视觉类型 Prompt（PROMPT_TYPE_VISION）

视觉任务的核心配置：
- `prompt_type: "PROMPT_TYPE_VISION"`
- `prompt_run_config.vision_fields_names: ["列名"]` — 指明哪一列是图片/视频 URL
- `model.model_id` — 必须是支持视觉的模型（用 `model-list --params '{"only_vision":true}'` 查）

> Prompt 文本里**不需要**写 `{{img_url}}` 占位符。系统会读 `vision_fields_names` 指定的列，把图片传给视觉模型。Prompt 描述任务即可。

### 视觉示例 — 图片内容理解

数据列：`id, title, img_url`

```bash
blueai-cli tools ai-batch openapi task-create --params '{
  "name": "图片内容分析",
  "data_source": {"data_source_id": "ds-xxx"},
  "prompt": {
    "prompt_type": "PROMPT_TYPE_VISION",
    "prompt_text": "分析这张图片。\n标题：{{title}}\n返回 JSON：{\"image_description\":\"\",\"main_objects\":[],\"scene_type\":\"\",\"text_in_image\":\"\",\"quality_score\":0}",
    "prompt_run_config": {
      "vision_fields_names": ["img_url"],
      "require_llm_result_json": true
    }
  },
  "model": {"model_id": "gpt-4o"}
}'
```

### 视觉模板 — 电商商品图

```json
{
  "prompt_type": "PROMPT_TYPE_VISION",
  "prompt_text": "分析商品图。商品标题：{{product_name}}\n返回 JSON：{\"product_type\":\"\",\"main_features\":[],\"color\":\"\",\"material\":\"\",\"usage_scenario\":\"\",\"target_audience\":\"\"}",
  "prompt_run_config": {"vision_fields_names": ["product_image_url"], "require_llm_result_json": true}
}
```

### 视觉模板 — 社媒图文综合分析

```json
{
  "prompt_type": "PROMPT_TYPE_VISION",
  "prompt_text": "综合分析图文帖子。标题：{{post_title}}\n正文：{{post_content}}\n返回 JSON：{\"topic\":\"\",\"image_content\":\"\",\"text_image_relevance\":\"高/中/低\",\"sentiment\":\"\",\"key_products\":[],\"target_audience\":\"\",\"content_quality\":0}",
  "prompt_run_config": {"vision_fields_names": ["post_cover_url"], "require_llm_result_json": true}
}
```

### 视觉模板 — OCR + 内容理解

```json
{
  "prompt_type": "PROMPT_TYPE_VISION",
  "prompt_text": "识别图片文字并理解内容。来源：{{source}}\n返回 JSON：{\"extracted_text\":\"\",\"text_type\":\"\",\"language\":\"\",\"key_information\":[],\"summary\":\"\"}",
  "prompt_run_config": {"vision_fields_names": ["img_url"], "require_llm_result_json": true}
}
```

### 视觉模板 — 多图对比

如果一行有多张图：

**方式一：多列**
```json
{"vision_fields_names": ["img_url_1", "img_url_2", "img_url_3"]}
```

**方式二：单列逗号分隔**
```csv
id,title,img_urls
1,产品图集,"https://a.com/1.jpg,https://a.com/2.jpg"
```
```json
{"vision_fields_names": ["img_urls"]}
```

## 模型选择

视觉模型按需查询（不要硬编码）：
```bash
# 所有视觉模型
blueai-cli tools ai-batch openapi model-list --params '{"only_vision":true}'

# 只要图片
blueai-cli tools ai-batch openapi model-list --params '{"vision_type":"image"}'

# 只要视频（gemini 系列支持）
blueai-cli tools ai-batch openapi model-list --params '{"vision_type":"video"}'
```

返回字段里关键的：`model_id`、`name`、`platform`、`vision_support`、`vision_types`、`reasoning_support`、`input_price` / `output_price`。

> Gemini 系列（`gemini-*`）要的是 `gcp_url`（`gs://`），不是 `https://`。详见 `models.md`。

## 视觉任务的注意事项

### 图片 URL 要求
- 必须公网可访问（除 Gemini 用 `gs://`）
- 支持 JPG/PNG/GIF/WebP，单张 < 20MB
- 注意签名 URL 的过期时间

### 数据文件格式
图片 URL 必须独立成列，列名要在 `vision_fields_names` 里精确引用：
```csv
id,title,content,img_url
1,产品测评,这款面霜很好用,https://example.com/img1.jpg
```

### 成本控制
- 视觉任务 token 消耗远高于纯文本
- 先小样本（10-20 条）测一把，看 `total_tokens` / `total_consume` 估算成本
- 简单任务用 `gpt-4o-mini`，复杂任务用 `gpt-4o`

### 常见错误

| 现象 | 排查 |
|---|---|
| 图片没被分析 | `prompt_type` 是不是 `PROMPT_TYPE_VISION` |
| `vision_fields_names` 报错 | 列名是否与数据文件完全一致（区分大小写） |
| 图片加载失败 | URL 公网可访问吗？是否过期？ |
| 模型报错 | 用 `model-list --params '{"only_vision":true}'` 确认模型支持视觉 |
| Gemini 任务失败 | 数据是 `gs://` 链接吗？`vision_fields_names` 是不是 `["gcp_url"]`？ |

## 异步批量提示

数据量大或多任务时，**别同步等**：

```bash
# 异步提交（立即返回 task_id，写进 ~/.blueai/tasks.json）
blueai-cli tools ai-batch openapi task-create --async --params '{...}'

# 一次性提交多组（批量 + 异步）
blueai-cli tools ai-batch openapi task-create --async --concurrency 5 --format ndjson --params '[
  {"_label":"批次1","data_source":{"data_source_id":"ds-a"},"prompt":{"prompt_text":"..."}},
  {"_label":"批次2","data_source":{"data_source_id":"ds-b"},"prompt":{"prompt_text":"..."}}
]'

# 收单
blueai-cli task wait --all --format ndjson
```

## 最佳实践

1. **Prompt 写明输出格式** — JSON schema 形式最稳，配合 `require_llm_result_json: true`。
2. **少量 few-shot 示例放进 prompt** — 标注一致性显著提升。
3. **先小样本验证** — 100 条以内的小数据集先跑一次，看输出是否符合预期再放量。
4. **用 `total_tokens` / `total_consume` 监控成本** — 任务终态里会返回。
5. **失败时去 `error.message` 找线索** — 错误码与处理见 `error-handling.md`。

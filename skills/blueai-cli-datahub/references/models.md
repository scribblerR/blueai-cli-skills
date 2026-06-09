# DataHub 模型选择（CLI 版）

DataHub 支持多家厂商的模型。**永远用 `model-list` 查实时列表**，不要硬编码 model_id（厂商会下线/上线模型）。

## 查模型

```bash
# 全部模型
blueai-cli tools ai-batch openapi model-list --params '{}'

# 只看视觉模型
blueai-cli tools ai-batch openapi model-list --params '{"only_vision":true}'

# 按视觉类型过滤
blueai-cli tools ai-batch openapi model-list --params '{"vision_type":"image"}'   # 图片
blueai-cli tools ai-batch openapi model-list --params '{"vision_type":"video"}'   # 视频
blueai-cli tools ai-batch openapi model-list --params '{"vision_type":"audio"}'   # 音频
```

### 返回字段
| 字段 | 含义 |
|---|---|
| `model_id` | 创建任务时填进 `model.model_id` |
| `name` | 人类可读名 |
| `platform` | 厂商（OpenAI / Anthropic / Google / Qwen / Doubao） |
| `vision_support` | 是否支持视觉 |
| `vision_types` | `["image"]` / `["video"]` / `["image","video"]` 等 |
| `reasoning_support` | 思维链支持 |
| `max_context_length` | 上下文上限（tokens） |
| `input_price` / `output_price` | 每百万 token 价格 |
| `currency` | 货币单位 |

提取关键信息：
```bash
blueai-cli tools ai-batch openapi model-list --params '{"only_vision":true}' \
  | jq -r '.data.data.models[] | "\(.model_id) | \(.name) | \(.vision_types | join("+")) | \(.input_price)/\(.output_price)"'
```

## 常见模型分类（参考，以 model-list 为准）

### OpenAI / Azure OpenAI（HTTPS URL）
- `gpt-4o`、`gpt-4o-mini`：图片，性价比高
- `gpt-5`、`gpt-5-mini`、`gpt-5.1`、`gpt-5.2`：图片
- `o1`、`o3`、`o3-pro`、`o4-mini`：图片+推理
- `o1-mini`、`o3-mini`：纯文本推理

### Google Gemini（**gs:// URL，必须 `gcp_url`**）
- `gemini-2.5-flash`：图片+视频+音频，多模态推荐
- `gemini-2.5-pro`：更强但更贵
- `gemini-3-flash-preview`、`gemini-3-pro-preview`：预览版

### Anthropic Claude（HTTPS URL）
- `global.anthropic.claude-sonnet-4-5-20250929-v1:0`
- `global.anthropic.claude-haiku-4-5-20251001-v1:0`
- `global.anthropic.claude-opus-4-5-20251101-v1:0`

### 阿里百炼 Qwen（HTTPS URL）
- `qwen-vl-max-latest`、`qwen-vl-plus-latest`：图片+视频
- `qwen-vl-ocr-latest`：专门做 OCR
- `qwen-max`、`qwen-plus`、`qwen-turbo-0624`：纯文本

### 火山引擎 Doubao（HTTPS URL）
- `bmc-Doubao-Seed-1.6`、`bmc-Doubao-Seed-1.6-thinking`：图片+视频
- `Doubao-1.5-vision-pro`、`Doubao-1.5-vision-pro-32k`
- `DeepSeek-R1`、`DeepSeek-V3`：纯文本推理

### Embedding（不能用于 task-create）
- `text-embedding-3-large` / `text-embedding-3-small` / `text-embedding-ada-002`

---

## URL 类型选择

DataHub 视觉任务里图片/视频字段有两种 URL 格式：

| 模型平台 | URL 字段 | 格式 |
|---|---|---|
| **Google Gemini** | `gcp_url` | `gs://bucket/path/image.jpg` |
| 其他全部 | `url` | `https://cdn.example.com/image.jpg` |

判断方式：以 `gemini-` / `gemini_` 开头的就是 Gemini。

### Gemini 任务的两个改动

视觉字段配置：
```json
{
  "prompt_run_config": {"vision_fields_names": ["gcp_url"]}
}
```

数据源里要有 `gcp_url` 这一列：
```csv
file_name,url,gcp_url
image.jpg,https://cdn.example.com/image.jpg,gs://bucket/path/image.jpg
```

> Media Storage skill 用 `--output-format datahub` 时会**同时**输出 `url` 和 `gcp_url` 两列，省得自己拼。

### Prompt 里引用图片 URL

视觉任务 prompt **不需要**写 `{{img_url}}`、`{{url}}`、`{{gcp_url}}`——`vision_fields_names` 已经告诉系统该读哪一列了。Prompt 文本只描述任务即可。

如果 prompt 里非要带 URL（比如想让模型在文本里也"看到"链接），那要保持一致：
- OpenAI/Claude/Qwen/Doubao：`{{url}}`
- Gemini：`{{gcp_url}}`

---

## 选模型决策树

```
需要分析图片或视频？
├─ 否 → 用文本模型（gpt-4o-mini / Doubao-pro / Qwen-plus 等便宜的）
└─ 是
    ├─ 数据是 gs:// 链接（Media Storage with --output-format datahub）→ Gemini
    └─ 数据是 https:// 链接
        ├─ 简单图片理解 + 成本敏感 → gpt-4o-mini
        ├─ 复杂多模态 / 推理 → gpt-4o / o3
        ├─ 视频分析 → gemini-2.5-flash 或 qwen-vl-max-latest
        └─ OCR 为主 → qwen-vl-ocr-latest
```

## 成本控制

- **先小样本** — 100 条以内跑一次，看 `total_tokens` / `total_consume`
- **简单任务用 mini 系列** — `gpt-4o-mini` 价格大约是 `gpt-4o` 的 1/10
- **`require_llm_result_json: true`** — 减少 LLM 啰嗦输出，省 output tokens

## 任务终态会带成本数据

```json
{
  "task_status": "TASK_STATUS_GENERATED_RESULT",
  "total_count": 1000,
  "total_tokens": 1234567,
  "total_consume": 12.34,
  "llm_consume_currency": "USD",
  "result_url": "https://..."
}
```

提取：
```bash
RESULT=$(blueai-cli task wait --ids '[123]')
echo "$RESULT" | jq '.data.data | {total_count, total_tokens, total_consume, llm_consume_currency}'
```

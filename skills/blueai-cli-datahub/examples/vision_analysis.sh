#!/usr/bin/env bash
# 视觉分析端到端：上传带图片 URL 的 CSV/Excel → 创建 PROMPT_TYPE_VISION 任务
#
# 数据文件要求：必须有一列存图片 URL（默认列名 img_url，可通过第 3 个参数覆盖）
#
# 用法：
#   ./vision_analysis.sh ./posts.xlsx                   # 默认 img_url 列、gpt-4o
#   ./vision_analysis.sh ./posts.xlsx post_cover_url    # 指定图片列
#   MODEL=gemini-2.5-flash ./vision_analysis.sh ./posts.xlsx gcp_url
#
# Gemini 模型注意：vision_fields 要写 gcp_url，数据源里必须有这一列。

set -euo pipefail

FILE="${1:?usage: vision_analysis.sh <file.xlsx|.csv> [vision_column] }"
VISION_COL="${2:-img_url}"
MODEL="${MODEL:-gpt-4o}"

[[ -f "$FILE" ]] || { echo "文件不存在：$FILE" >&2; exit 1; }

# Gemini 自动适配检测
if [[ "$MODEL" == gemini-* ]] && [[ "$VISION_COL" != "gcp_url" ]]; then
  echo "⚠️  检测到 Gemini 模型 ($MODEL) 但视觉列不是 gcp_url。" >&2
  echo "    Gemini 只接受 gs:// 链接，请确认数据源里 $VISION_COL 列是 gs:// 格式。" >&2
fi

# Prompt 文本不要写 {{img_url}} - 系统通过 vision_fields_names 自动取
PROMPT='分析这张图片。

如果有标题字段，请结合标题理解：{{title}}

返回 JSON：{
  "image_description": "图片内容描述",
  "main_objects": ["物体1", "物体2"],
  "scene_type": "场景类型",
  "text_in_image": "图中文字（如有）",
  "quality_score": 0
}'

echo "[1/3] 上传 $FILE"
DS_ID=$(blueai-cli tools ai-batch openapi upload-file \
  --params "{\"file_name\":\"$(basename "$FILE")\"}" \
  --file "$FILE" \
  | jq -r '.data.data.data_source_id')
echo "      data_source_id=$DS_ID"

echo "[2/3] 创建视觉任务（model=$MODEL, vision=[$VISION_COL]）"
RESULT=$(blueai-cli tools ai-batch openapi task-create --params "$(jq -n \
  --arg ds "$DS_ID" --arg prompt "$PROMPT" --arg model "$MODEL" --arg col "$VISION_COL" '{
    name: "视觉分析",
    data_source: {data_source_id: $ds},
    prompt: {
      prompt_type: "PROMPT_TYPE_VISION",
      prompt_text: $prompt,
      prompt_run_config: {
        vision_fields_names: [$col],
        require_llm_result_json: true
      }
    },
    model: {model_id: $model}
  }')")

# 3. 输出
TASK_ID=$(echo "$RESULT" | jq -r '.data.data.task_id')
RESULT_URL=$(echo "$RESULT" | jq -r '.data.data.result_url // ""')
TOTAL=$(echo "$RESULT" | jq -r '.data.data.total_count // 0')
TOKENS=$(echo "$RESULT" | jq -r '.data.data.total_tokens // 0')

echo "[3/3] 任务完成"
echo "  task_id : $TASK_ID"
echo "  数据条数 : $TOTAL"
echo "  消耗     : $TOKENS tokens"
[[ -n "$RESULT_URL" ]] && echo "  下载：[结果文件]($RESULT_URL)"

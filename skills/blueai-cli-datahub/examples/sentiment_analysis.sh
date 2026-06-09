#!/usr/bin/env bash
# 端到端：上传 CSV → 创建情感分析任务 → 等待结果 → 输出下载链接
#
# 用法：
#   ./sentiment_analysis.sh ./reviews.csv content
#   $1 = 数据文件路径
#   $2 = prompt 里的列名（可选，默认 content）

set -euo pipefail

FILE="${1:?usage: sentiment_analysis.sh <file.csv> [column_name]}"
COLUMN="${2:-content}"
MODEL="${MODEL:-gpt-4o-mini}"

[[ -f "$FILE" ]] || { echo "文件不存在：$FILE" >&2; exit 1; }

PROMPT="分析以下文本的情感倾向。\n\n${COLUMN}内容：{{${COLUMN}}}\n\n返回 JSON：{\"sentiment\":\"正面/负面/中性\",\"confidence\":0.0,\"reason\":\"\"}"

# 1. 上传文件
echo "[1/3] 上传 $FILE"
DS_ID=$(blueai-cli tools ai-batch openapi upload-file \
  --params "{\"file_name\":\"$(basename "$FILE")\"}" \
  --file "$FILE" \
  | jq -r '.data.data.data_source_id')

echo "      data_source_id=$DS_ID"

# 2. 创建任务（同步：CLI 自动轮询到终态）
echo "[2/3] 创建任务（model=$MODEL）"
RESULT=$(blueai-cli tools ai-batch openapi task-create --params "$(jq -n \
  --arg ds "$DS_ID" --arg prompt "$PROMPT" --arg model "$MODEL" '{
    name: "情感分析",
    data_source: {data_source_id: $ds},
    prompt: {
      prompt_text: $prompt,
      prompt_run_config: {require_llm_result_json: true}
    },
    model: {model_id: $model}
  }')")

# 3. 输出结果摘要
TASK_ID=$(echo "$RESULT"  | jq -r '.data.data.task_id')
STATUS=$(echo "$RESULT"   | jq -r '.data.data.task_status')
RESULT_URL=$(echo "$RESULT" | jq -r '.data.data.result_url // ""')
TOTAL=$(echo "$RESULT"    | jq -r '.data.data.total_count // 0')
TOKENS=$(echo "$RESULT"   | jq -r '.data.data.total_tokens // 0')
COST=$(echo "$RESULT"     | jq -r '.data.data.total_consume // 0')
CURRENCY=$(echo "$RESULT" | jq -r '.data.data.llm_consume_currency // ""')

echo "[3/3] 任务完成"
echo "  task_id : $TASK_ID"
echo "  status  : $STATUS"
echo "  数据条数 : $TOTAL"
echo "  消耗     : $TOKENS tokens / $COST $CURRENCY"
if [[ -n "$RESULT_URL" ]]; then
  echo ""
  echo "  下载链接：[结果文件]($RESULT_URL)"
fi

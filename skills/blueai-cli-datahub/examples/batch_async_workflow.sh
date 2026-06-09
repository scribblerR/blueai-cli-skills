#!/usr/bin/env bash
# 异步批量工作流：N 个任务并发提交（fire-and-forget）→ 后续 task wait --all 一次收齐
# 这是 agent 工作流的最优姿势 — 提交完去做别的事，回头收单。
#
# 演示场景：
# - 同一份数据，跑 3 种不同分析（情感 / 关键词 / 分类）
# - 全部异步提交，立即返回 task_id
# - 然后用 blueai-cli task wait --all 等所有任务结束
#
# 用法：
#   ./batch_async_workflow.sh ./reviews.csv

set -euo pipefail

FILE="${1:?usage: batch_async_workflow.sh <file.csv>}"
COLUMN="${2:-content}"

[[ -f "$FILE" ]] || { echo "文件不存在：$FILE" >&2; exit 1; }

echo "=== 步骤 1：上传数据文件 ==="
DS_ID=$(blueai-cli tools ai-batch openapi upload-file \
  --params "{\"file_name\":\"$(basename "$FILE")\"}" \
  --file "$FILE" \
  | jq -r '.data.data.data_source_id')
echo "data_source_id=$DS_ID"
echo ""

echo "=== 步骤 2：批量异步提交 3 个任务（情感 / 关键词 / 分类） ==="
# 用 batch + async：一次 CLI 调用同时提交 3 个独立任务
# - _label：CLI 把它原样回显，方便 agent 关联结果
# - --concurrency 3：并发提交
# - --async：每个任务立即返回 task_id，不等执行完
# - --format ndjson：每完成一个提交输出一行 JSON

PARAMS=$(jq -n --arg ds "$DS_ID" --arg col "$COLUMN" '[
  {
    _label: "sentiment",
    name: "情感分析",
    data_source: {data_source_id: $ds},
    prompt: {
      prompt_text: "分析情感：{{\($col)}}\n返回 JSON：{\"sentiment\":\"正面/负面/中性\",\"confidence\":0}",
      prompt_run_config: {require_llm_result_json: true}
    }
  },
  {
    _label: "keywords",
    name: "关键词提取",
    data_source: {data_source_id: $ds},
    prompt: {
      prompt_text: "提取关键词：{{\($col)}}\n返回 JSON：{\"keywords\":[],\"summary\":\"\"}",
      prompt_run_config: {require_llm_result_json: true}
    }
  },
  {
    _label: "category",
    name: "文本分类",
    data_source: {data_source_id: $ds},
    prompt: {
      prompt_text: "分类：{{\($col)}}\n类别：产品咨询/售后/投诉/其他\n返回 JSON：{\"category\":\"\"}",
      prompt_run_config: {require_llm_result_json: true}
    }
  }
]')

blueai-cli tools ai-batch openapi task-create \
  --async --concurrency 3 --format ndjson \
  --params "$PARAMS"
# stdout 是每个 task 的 NDJSON：
# {"index":0,"label":"sentiment","ok":true,"data":{"data":{"task_id":...}}}
# 这些已经被 CLI 自动写进 ~/.blueai/tasks.json 了，下面直接 task wait 就行

echo ""
echo "=== 步骤 3：等所有 pending 任务完成（agent 这里可以先去干别的） ==="
echo "（演示：直接收单。实际工作流可以在这里穿插其他工具调用。）"
echo ""

# task wait --all：扫描 ~/.blueai/tasks.json 里所有 pending 任务，并发等
# --concurrency 3：同时轮询 3 个
# --format ndjson：每完成一个输出一行
blueai-cli task wait --all --concurrency 3 --format ndjson | tee /tmp/datahub_batch_results.ndjson

echo ""
echo "=== 收单完毕 ==="
echo "结果保存在：/tmp/datahub_batch_results.ndjson"
echo ""
echo "提取所有 result_url："
jq -r 'select(.data.data.result_url) | "\(.label // .task_id): \(.data.data.result_url)"' \
  /tmp/datahub_batch_results.ndjson

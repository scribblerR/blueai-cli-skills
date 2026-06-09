#!/usr/bin/env bash
# 批量出图 + 一次性收口（agent 最佳姿势：先全发出去，回头统一收）
#
# 任何 aigc 命令的 --params 传 JSON 数组即批量并发；配 --async + NDJSON + task wait --all 最省事。
# _label 会原样回显在每条结果里方便对账（CLI 自动剥离不发给后端）。
set -euo pipefail

# ── 批量提交（--async 立即返回各 task_id，写入 ~/.blueai/tasks.json）──────────────
blueai-cli aigc image text2image jimeng v4 \
  --params '[
    {"_label":"banner-a","model":"doubao-seedream-4-0-250828","prompt":"夏季促销横幅 A，清爽蓝","size":"2K"},
    {"_label":"banner-b","model":"doubao-seedream-4-0-250828","prompt":"夏季促销横幅 B，活力橙","size":"2K"},
    {"_label":"banner-c","model":"doubao-seedream-4-0-250828","prompt":"夏季促销横幅 C，简约白","size":"2K"}
  ]' \
  --concurrency 3 --async --format ndjson
# 输出：每行一个 {"index":..,"label":"banner-a","ok":true,"data":{...task_id...}}
# 末行：{"batch_summary":{"total":3,"succeeded":3,"failed":0}}

# ── 去干别的事…… 回头一次性等所有挂起任务 ─────────────────────────────────────
blueai-cli task wait --all --format ndjson
# 每完成一个输出一行（含终态结果）；也可 blueai-cli task list 看状态、task wait --ids '["..."]' 等指定几个。

# 同步接口（如 llm-relay 图像 generate/edit）不用 --async，--params 传数组即并发直返，无需 task wait。
# --fail-fast：首个失败后停止调度新项并以非零码退出（CI/批处理用）。

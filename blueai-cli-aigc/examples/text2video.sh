#!/usr/bin/env bash
# 中文文生视频（以可灵为例）—— 演示标准回路：discover(schema) → fill → call → 取片
# 选型理由见 references/video.md；本脚本可直接改 prompt 跑。
set -euo pipefail

# 1) discover —— 拿当前 model 枚举 + 每参数的 enum/约束（requestBody 段是权威源）
#    重点看 model_name 各档的时长/分辨率/音频能力、duration 的 enum、mode/aspect_ratio。
blueai-cli schema aigc.video.text2video.kling --resolve-refs | jq '.data.requestBody'

# 2) fill + 预检 —— dry-run 确认 body 形状（不消耗额度）
PARAMS='{"model_name":"kling-v3","prompt":"国风水墨，一只锦鲤跃出水面，慢镜头","duration":"10","mode":"pro","aspect_ratio":"16:9"}'
blueai-cli aigc video text2video kling --params "$PARAMS" --dry-run

# 3) call —— async 接口默认前台轮询到终态(succeeded/failed)才返回
#    产物 URL 在双层 data 里，确切字段名以 schema 的响应结构为准（多为 data.data.task_result.videos[].url）
blueai-cli aigc video text2video kling --params "$PARAMS" --format json \
  | jq -r '.data.data.task_result.videos[0].url // .data.data // .data'

# —— 变体：后台跑，先拿 task_id 去干别的，回头收口 ——
# blueai-cli aigc video text2video kling --params "$PARAMS" --async        # 立即返回 task_id
# blueai-cli task wait --all --format ndjson                                # 一次性等所有挂起任务
# blueai-cli task status <task_id> --watch                                  # 盯单个

# 结果链接常 24h 过期 —— 需要留存就转存：见 examples 同级的 media-storage 用法或 blueai-cli-media-storage skill

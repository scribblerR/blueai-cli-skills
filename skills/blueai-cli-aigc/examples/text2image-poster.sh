#!/usr/bin/env bash
# 中文海报 / 营销图（文生图）—— 中文帧内文字渲染选 即梦 Seedream 或 通义万相
# 选型见 references/image.md（中文出字这两家最强；Qwen 不纳入）。
set -euo pipefail

# ── 方案 A：即梦 Seedream（中文文字引擎强；注意版本谱有两套接口，schema 确认走哪套）──
# 先查当前可用版本与 size 口径：blueai-cli schema aigc.image.text2image.jimeng.v4 --resolve-refs
# size 用官方口径（auto/1K/2K/4K 或 宽x高，dims 须 16 倍数），不是 gpt-image 三档。
blueai-cli aigc image text2image jimeng v4 --params '{
  "model": "doubao-seedream-4-0-250828",
  "prompt": "电商促销主视觉，标题文字「夏日清凉季」，副标题「全场五折起」，明亮通透，留白",
  "size": "2K"
}' --format json | jq -r '.data.data.image_urls[0] // .data.data // .data'

# ── 方案 B：通义万相（原生中文理解最佳，pro 支持 4K；单一 messages 入口）──────────
# blueai-cli schema aigc.image.image-generation.aliyun --resolve-refs   # 看 model/messages/parameters
# blueai-cli aigc image image-generation aliyun --params '{
#   "model":"wan2.7-image-pro",
#   "messages":[{"role":"user","content":[{"text":"中式茶饮海报，标题「一盏清欢」，水墨风"}]}],
#   "parameters":{"size":"2K","watermark":false}
# }'

# 两家都是 async：默认前台轮询到终态返回；结果图 URL 常 24h 过期，需留存就转存(media-storage)。
# 即梦组图（一次多张）须显式 sequential_image_generation:"auto" + max_images，否则只出单图。

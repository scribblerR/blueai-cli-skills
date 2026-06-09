#!/usr/bin/env bash
# 局部改图 / 图像编辑（gpt-image-2 经 relay，multipart）—— 已实测可跑通
#
# 适合：精确 mask 局部重绘、多参考图合成、英文创意编辑。中文出字请改用即梦/万相。
# 这条端点是同步 multipart：CLI 用 --file 传本地 PNG。编辑耗时约 1 分钟，
# x-cli 已为该接口配 30 分钟请求超时，【无需】手动加 --timeout。
set -euo pipefail

INPUT_PNG=./input.png   # 本地 PNG。官方约束：像素 65.5万–829万、边长 16 倍数、≤3840px、长短边比≤3:1
# 可选遮罩：MASK_PNG=./mask.png（完全透明区域=要编辑的位置；与原图同尺寸）

# 当前可用 model（实测现役 gpt-image-2，最新；别用 spec example 里的旧 gpt-image-1）：
#   blueai-cli llm models --format json | grep -i gpt-image
# 参数 schema：blueai-cli schema aigc.image.openai-edit.llm-relay --resolve-refs

blueai-cli aigc image openai-edit llm-relay \
  --file "$INPUT_PNG" \
  --params '{"model":"gpt-image-2","prompt":"把背景换成晴朗海滩，主体保持不变","size":"1024x1024"}' \
  --format json \
  | jq -r '.data.data[0].b64_json' | base64 --decode > ./edited.png
echo "已写出 ./edited.png"

# 关于 mask 精确 inpaint：OpenAI edits 的 mask 是【第二个 multipart 文件字段】，
# 而当前 CLI 的 --file 只暴露【单个】文件(映射到主 image 字段)，**经 CLI 传不了 mask**。
# 需要带 mask 的像素级 inpaint → 走 raw api(blueai-cli api，自行拼 multipart)，或改用 Nano Banana 的
# 内联多图/对话式编辑(gemini-generate)。不带 mask 时，靠 prompt 引导编辑(如本例)即可经 CLI 跑通。
# 多参考图合成：gpt-image-2 输入高保真不降采样(不同于已下线的 gpt-image-1)。

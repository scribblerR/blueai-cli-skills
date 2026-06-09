#!/usr/bin/env bash
# 电商短视频 + 用户「自己的中文配音」—— 跨模态全链路（最容易选错的场景）
#
# 关键认知（见 SKILL.md「关键分叉」）：图生视频模型不吃外部音轨，它的"音频"是模型自造的。
# 用户已有配音文案时，正确做法 = 图生视频(无声) + TTS 出语音 + video-tools 合轨。
# 不要指望可灵/即梦把你的 TTS 音频并进它生成的视频。
set -euo pipefail

WORK=./_aigc_work; mkdir -p "$WORK"
PRODUCT_IMG=./product.jpg          # 你的本地产品图
VOICEOVER_TEXT="夏季新品，清爽不油腻，限时五折"   # 你的配音文案

# ── 步 1：本地图 → 公网 URL（图生视频输入必须是公网可 GET 的 URL）────────────────
SIZE=$(wc -c < "$PRODUCT_IMG")
IMG_URL=$(blueai-cli media-storage file upload --file "$PRODUCT_IMG" --params "{\"file_size\":$SIZE}" \
  | jq -r '.data.data.url // .data.data.file_url')
echo "图已上传: $IMG_URL"

# ── 步 2：图生视频（无声，async 默认轮询到终态）──────────────────────────────────
# 先 schema 查 image2video 的当前 model 与参数：blueai-cli schema aigc.video.image2video.kling --resolve-refs
VID_URL=$(blueai-cli aigc video image2video kling \
  --params "{\"model_name\":\"kling-v2-6\",\"image\":\"$IMG_URL\",\"prompt\":\"产品缓慢旋转展示，柔光\",\"mode\":\"pro\",\"duration\":\"5\"}" \
  | jq -r '.data.data.task_result.videos[0].url')
echo "无声视频: $VID_URL"

# ── 步 3：TTS 合成「我的配音」（中文情感 TTS 选 minimax；schema 查当前 model/voice）──
# 注：CLI 把流式 TTS 包装成 async，非实时；批量合成无碍。
AUDIO_URL=$(blueai-cli aigc audio tts minimax \
  --params "{\"model\":\"speech-2.6\",\"text\":\"$VOICEOVER_TEXT\",\"voice_setting\":{\"voice_id\":\"male-qn-qingse\"}}" \
  | jq -r '.data.data.audio_url // .data.data.data.audio')   # 字段名以 schema 响应为准
echo "配音音频: $AUDIO_URL"

# ── 步 4：合轨（视频+音轨 → 成片）属后处理，不在 aigc，走 video-tools ────────────────
# 合成接口参数（模板 id 等）由模板维护方提供；见 blueai-cli-video-tools skill。
blueai-cli tools video-tools synthesis --params "{
  \"project_template_id\": 0, \"task_template_id\": 0,
  \"video_urls\": [[\"$VID_URL\",\"pre\"]], \"material_num_task_need\": 1,
  \"audio_url\": \"$AUDIO_URL\"
}" --format json | jq -r '.data.data.url // .data'

# 提示：步 2/3 无依赖，可都加 --async 先发出去，再 blueai-cli task wait --all 收口，最后再合轨。

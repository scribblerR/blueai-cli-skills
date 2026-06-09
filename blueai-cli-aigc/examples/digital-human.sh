#!/usr/bin/env bash
# 数字人口播 —— 图 + 音频是硬前置
#
# 选型（见 references/video.md / audio.md）：
#  - 可灵 avatar-image2video：人物图 + 音色(audio_id 试听音)或音频文件，二者互斥
#  - GAGA avatar-h1-pro：音频驱动数字人，最长 60s，多语种（图+音频经 /v1/assets 上传后引用）
set -euo pipefail

# ── 可灵数字人 ────────────────────────────────────────────────────────────────
# 前置：人物图须公网 URL（本地图先 media-storage 上传）；音频侧二选一。
# schema：blueai-cli schema aigc.video.avatar-image2video.kling --resolve-refs
PERSON_IMG_URL="https://your-cdn/person.jpg"

# 音频路线 1：用平台音色试听音 audio_id（先查音色：aigc audio preset-voices kling）
blueai-cli aigc video avatar-image2video kling --params "{
  \"image\": \"$PERSON_IMG_URL\",
  \"audio_id\": \"<从 preset-voices 选的音色 id>\",
  \"prompt\": \"自然口播，微笑\"
}" --format json | jq -r '.data.data.task_result.videos[0].url'

# 音频路线 2：用已有音频文件（与 audio_id 互斥；字段名以 schema 为准，常为 sound_file/audio_url）
# blueai-cli aigc video avatar-image2video kling --params "{\"image\":\"$PERSON_IMG_URL\",\"sound_file\":\"https://your-cdn/voice.mp3\"}"

# ── GAGA 数字人（长口播 60s）──────────────────────────────────────────────────
# GAGA 图与音频共用 /v1/assets 上传体系，拿 asset id 后填进 avatar 生成；音频也可用 gaga 的 TTS 现造。
# 先 schema：blueai-cli schema aigc.video.<gaga avatar 路径> --resolve-refs（按 spec list 找当前路径）

# 想要"我自己的配音文案"驱动口型：先 TTS 出音频 → 再喂数字人；见 voice-clone-tts.sh / ecommerce-video-with-voiceover.sh

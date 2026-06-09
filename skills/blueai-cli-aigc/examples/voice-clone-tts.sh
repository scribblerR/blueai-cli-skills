#!/usr/bin/env bash
# 声音克隆 + 用克隆音色配音（minimax，三段式）
#
# 链路：上传样本拿 file_id → voice_clone 绑定自定义 voice_id → 用该 voice_id 调 TTS。
# minimax 克隆门槛低（约 10s 样本即可）。schema 查当前参数：
#   blueai-cli schema aigc.audio.voice.clone.minimax --resolve-refs
#   blueai-cli schema aigc.audio.tts.minimax --resolve-refs
set -euo pipefail

SAMPLE=./voice_sample.mp3      # 你的音色样本（干净单人声，约 10s+）
MY_VOICE_ID="my_brand_voice_01"  # 自定义音色 id（你起名）
TEXT="欢迎收看本期节目，我们开始吧"

# ── 步 1：上传样本拿 file_id（purpose=voice_clone）──────────────────────────────
SIZE=$(wc -c < "$SAMPLE")
FILE_ID=$(blueai-cli aigc audio file minimax --file "$SAMPLE" \
  --params "{\"file_size\":$SIZE,\"purpose\":\"voice_clone\"}" \
  | jq -r '.data.data.file.file_id // .data.data.file_id')
echo "样本 file_id: $FILE_ID"

# ── 步 2：克隆音色（绑定 file_id → 自定义 voice_id）─────────────────────────────
blueai-cli aigc audio voice clone minimax \
  --params "{\"file_id\":$FILE_ID,\"voice_id\":\"$MY_VOICE_ID\"}" --format json | jq '.data.data'
# 注：复刻音色须"成功合成一次后"才会在 get_voice 列表出现。

# ── 步 3：用克隆出的 voice_id 合成配音 ─────────────────────────────────────────
blueai-cli aigc audio tts minimax \
  --params "{\"model\":\"speech-2.6\",\"text\":\"$TEXT\",\"voice_setting\":{\"voice_id\":\"$MY_VOICE_ID\"}}" \
  --format json | jq -r '.data.data.audio_url // .data.data'

# 火山(volcengine)路线门槛也低（5s ICL），但要先在控制台开通+买音色槽位拿 speaker_id，见 references/audio.md。

# AIGC 音频选型与前置链路（reference）

> 选型结论稳定，具体 model_id / 音色 id / 采样率 / 参数枚举 / 计费以 `blueai-cli schema <path> --resolve-refs` 实时为准——下文刻意不硬编码这些会 rot 的值。
> 音频是异构域（TTS / 声音克隆 / 音乐 / ASR / 音效），先按子能力过滤厂商，再按场景挑首选。

## 子能力覆盖总览（先用它过滤——别选不具备该子能力的厂商）

> ✅=经网关可用；部分=能力存在但被网关精简/受限；❌=不暴露或不具备。

| 厂商 | TTS | 声音克隆 | 音乐/歌词 | ASR识别 | 文生音效 | 视频生音效 |
|---|---|---|---|---|---|---|
| azure | ✅ 140+语言/500+音色+批量异步 | ❌ | ❌ | ❌ | ❌ | ❌ |
| minimax | ✅ 40+语种/语气词标签 | ✅ 10秒样本 | ✅ 带词带人声/翻唱+歌词 | ❌ | ❌ | ❌ |
| sensetime | ✅ 仅中文/70+音色/10+情感 | 部分（官方有，网关未暴露） | ❌ | 部分（官方有，网关未暴露） | ❌ | ❌ |
| volcengine | ✅ 多语种，仅 V1 子集 | ✅ 5秒样本（需控制台开通） | ❌ | 部分（ATA 字幕打轴=强制对齐，非转写） | ❌ | ❌ |
| kling | ✅ 仅 zh/en | ✅ 5-30s 单人声 | ❌ | ❌ | ✅ 3-10s | ✅ Kling-Foley 领先 |
| gaga | ✅ 40+多语种音色（仅 voiceId+text） | ❌ API 无端点 | ❌ | ❌ | ❌ | ❌ |
| aliyun | ❌ | ❌ | ❌ | ✅ 极速版转写+热词库 | ❌ | ❌ |
| llm-relay | 部分（TTS/Realtime 被 hidden） | ❌ | ❌ | ✅ Whisper/gpt-4o，转录+仅译英 | ❌ | ❌ |

**唯一选择记死**：音乐/歌曲 → 只有 minimax；文生/视频生音效 → 只有 kling。

## 厂商一句话画像

| 厂商 | blueai 路径前缀 | 定位 | 适合场景 |
|---|---|---|---|
| azure | `aigc.audio.{tts,batch-tts,voice-list}.azure` | 多语种 TTS 之王 | 海外多语种配音、有声书规模化、批量字幕配音 |
| minimax | `aigc.audio.{tts,voice.clone,voice.get,file,music-generation,lyrics-generation}.minimax` | 音频全能（TTS+10s克隆+整曲音乐三合一） | 中文短视频配音+配乐一站式、低样本复刻、原创/翻唱 |
| sensetime | `aigc.audio.tts.sensetime` | 中文情感 TTS（仅普通话） | 中文情感播客/有声书/客服 |
| volcengine | `aigc.audio.{tts,mega-tts-upload-audio,ata,template-list}.volcengine` | 豆包语音（拟人+5s克隆+歌词打轴），仅 V1 子集 | 中文拟人配音、低样本克隆、卡拉OK逐字对齐(ATA) |
| kling | `aigc.audio.{text-to-audio,video-to-audio,text2speech,custom-voice,preset-voices}.kling` | 音效/配乐闭环最全 | 视频配音效/BGM、文生短音效、配套数字人音色 |
| gaga | `aigc.audio.generation.gaga`（+`aigc.video.*`） | 数字人配套 TTS（音视频同源） | 数字人口播配音、多语种播客旁白 |
| aliyun | `aigc.audio.{asr,hotword-library.*}.aliyun` | 极速版 ASR（30min→约10s）+热词库 | 录音转写、字幕生成、准实时质检 |
| llm-relay | `aigc.audio.{transcribe,translate}.llm-relay` | OpenAI Whisper 转录/译英（同步、本地文件直传） | 多语种转录、srt/vtt 字幕直出、译英 |

## 按子能力选型（首选 + 备选 + 理由 + 风险）

- **TTS 多语言/海外配音**：首选 **azure**（语言覆盖业界最广、批量 API 成熟，95% 任务 120s 内）。备选 **minimax**（40+语种、单 voice_id 跨语种、语气词标签自然）、**gaga**（单音色常跨 6-13 语言、接口极简）。风险：azure "700+ HD 音色"名实不符，须先 `voice-list` 实测可用项；流式未暴露。

- **TTS 中文/情感表现力**：首选 **minimax**（9 情绪 + 2.8 系列 19 种语气词"会呼吸"，中文第一梯队）。备选 **sensetime**（10+ 情感、同音色多变体覆盖客服/广告/播客）、**volcengine**（豆包拟人度行业领先，抖音/剪映已验证）。风险：volcengine **emotion 字段经网关未透传**（要情感须走原生 V3）；sensetime 成熟度待观察。

- **TTS 超低延迟/流式实时**：⚠️ **网关层面均被削弱**。官方最强是 minimax(<250ms token流) 与 sensetime(<500ms 首包 SSE+WS)，但 **minimax/kling/volcengine 的流式经网关被包装成 async 轮询**，实时性在 CLI 路径上大幅丧失。结论：真·实时交互 **CLI 路径不适合，须直连厂商原生流式**；若必须走 CLI，选 sensetime/azure（spec 标 sync，少一跳）损耗相对最小。

- **声音克隆 低样本/快速复刻**：首选 **volcengine**（5 秒录音、秒级复刻、无训练等待）与 **minimax**（10 秒样本、Fluent LoRA 可修复带口音源、最多 4 音色混合）。备选 **kling**（5-30s 单人声，可引用平台历史视频作音源，与对口型/数字人打通）。风险：volcengine 前置重（控制台开通+购槽位）；minimax 链路长（三段式，首次合成后才可查）；**gaga/sensetime 经网关不可克隆**（写死）。

- **音乐/歌曲（带词带人声）**：**唯一 minimax**。原创/纯音乐/翻唱三模式 + lyrics_optimizer 自动写词 + 100+ 乐器 + 44.1kHz 整曲，配套独立歌词接口（write_full_song/edit），有免费档（music-2.6-free / music-cover-free）。风险：音乐时长上限、商用 royalty-free 等关键项 spec 未暴露，依赖聚合口径。

- **ASR 录音转写/字幕**：首选 **aliyun**（极速版 30min 约 10s 同步返回、句级+词级时间戳、热词库 Weight 精调、MP4 可直喂视频音轨）。备选 **llm-relay/Whisper**（约 99 语言、srt/vtt 直出、本地文件直传、同步）。风险：**两家均无说话人分离**；aliyun 语种须控制台预配（API 不可切）、单文件 ≤2h/100MB；llm-relay ≤25MB（长音频自行 ffmpeg 切片）、gpt-4o-transcribe 有英语强制 bug。

- **文生音效·视频配音效**：**唯一 kling**。文生音效（text-to-audio，3-10s，prompt≤200）+ 视频生音效（Kling-Foley，立体声/帧级音画对齐/ASMR/音效+BGM 双提示词，公开基准领先）。风险：文生音效无 model 档位、封顶 10s；长音效/长 BGM 须走视频生音效（**依赖先有一段视频**）。

- **数字人/视频配套配音**：首选 **gaga**（TTS 产出的 audio id 直接喂回 avatar 数字人 conditions，零落地、音视频同源最简）。备选 **kling**（音色克隆/官方库与对口型 lip-sync 打通）、**volcengine cv-submit**（OmniHuman/RealMan，属"音频驱动视频"，音频 ≤35s）。风险：gaga 无克隆、无速率/音调/情感控制（仅 voiceId+text）。

## 前置依赖链路（调用前必做）

| 目标能力 | 前置步骤 | 对应 blueai-cli 命令 |
|---|---|---|
| azure 多语种/批量 TTS | 先查音色列表拿 ShortName + 校验 StyleList；长文本走 batch 轮询 | `voice-list.azure` → `tts.azure`；`batch-tts.azure`（自动 5s 轮询） |
| minimax 声音克隆（三段式） | ① files/upload(purpose=voice_clone) 拿 file_id → ② voice_clone 绑定自定义 voice_id → ③ **首次 TTS 成功后**才能在 voice.get 查到 | `file.minimax` → `voice.clone.minimax` → `tts.minimax` |
| minimax 翻唱音乐 | 直接传公网 audio_url 或 base64，无需上传 | `music-generation.minimax`（model=music-cover） |
| volcengine 声音克隆 | ①（控制台）开通声音复刻+购/领槽位拿空 speaker_id → ② 上传 5-15s 训练音频 → ③ voice_type=speaker_id + cluster=volcano_icl 合成 | （控制台）→ `mega-tts-upload-audio.volcengine` → `tts.volcengine` |
| volcengine 系统音色 | 先拉 template-list 取 param 当 voice_type，cluster=volcano_tts | `template-list.volcengine` → `tts.volcengine` |
| kling TTS | 先取 voice_id：查预置 或 建自定义音色 | `preset-voices.kling` / `custom-voice.kling` → `text2speech.kling` |
| kling 视频生音效 | **必须先有视频**：上传 video_url 或用 30 天内可灵 video_id（3-20s） | 先 `aigc.video.*.kling` → `video-to-audio.kling` |
| gaga 数字人闭环 | TTS 的 `data.id` **本身即 audio asset id**，无需二次上传，直接填视频 conditions[].content(type=audio)；现成音频走 upload-asset(<60s, MP3/WAV/OGG) | `audio.generation.gaga` → `video.generation.gaga`（avatar-h1 音频必填） |
| aliyun 带热词 ASR | ① 建热词库(UsageScenario=ASR) 拿 HotwordLibraryId → ② 识别填 vocabulary_id；音频须公网 URL（推荐 OSS 公共读，不支持本地/IP/含空格） | `hotword-library.create.aliyun` → `asr.aliyun` |
| llm-relay 转录/译英 | multipart 本地 `--file`（**不支持 URL 直传**）；>25MB 先 ffmpeg 切片；要时间戳/字幕必须 whisper-1 + verbose_json/srt/vtt | `transcribe.llm-relay` / `translate.llm-relay` |

## 风险红线

1. **流式 TTS 被网关包成 async 轮询，削弱实时**：minimax（官方 <250ms token 流 → x-cli 标 async）、kling（spec description 误写"同步返回"，实为 async）、volcengine（官方 query 本同步 → spec 标 async 轮询）。实时场景须直连原生流式。
2. **spec 陈旧（调用前以 schema 实时为准，勿缓存）**：sensetime model 名过期（spec `SenseAudio-TTS-1.0` vs 官方 `senseaudio-tts-1.5-*`）+ 采样率枚举含已废 48000/缺 8000/22050/44100；volcengine 仅 V1 子集（model_type 缺值 5、无 emotion/pitch_ratio/SSML 透传）；azure Neural HD 单价 spec 旧值。
3. **llm-relay translate 仅译英文 + 仅 whisper-1 + 单文件 ≤25MB**（多语种互译做不到，长音频须切片）。
4. **aliyun ASR 无说话人分离**（多人会议分角色做不到，须换百炼 Paraformer，spec 未封装）；语种须控制台预配，API 不可切。
5. **gaga 经网关不可克隆**（API 无端点，仅产品网页端）；**无速率/音调/情感/SSML** 任何细粒度控制（仅 voiceId+text）；输出采样率/格式/时长上限/商用条款官方零明文；名人音色有肖像/声音权合规风险。
6. **sensetime 系统音色仅中文普通话**（外文须另选厂商）。
7. **kling 独立 TTS 仅 zh/en 两语种**（远窄于其视频侧多语言原生配音）；采样率/比特率官方未公开。
8. **互通性存疑须实测**：aliyun 热词库(IMS/ICE)↔极速版(NLS) 官方无交叉背书，建库后取 HotwordLibraryId 填 vocabulary_id 跑一条验证。

## 审计音色/模板的命令入口

`voice-list.azure`、`template-list.volcengine`、`preset-voices.kling`、`voice.get.minimax`（复刻音色须用过一次才可查）。具体 model_id / voice_id / 采样率 / 参数枚举 / 单价一律 `blueai-cli schema <path> --resolve-refs` 实时获取。

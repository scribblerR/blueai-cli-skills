---
name: blueai-cli-aigc
description: >
  通过 blueai-cli 调用 AIGC 生成能力并做厂商/模型选型——图像、视频、音频三模态合一。
  当用户要：文生图/图生图、文生视频/图生视频/首尾帧/数字人/对口型/视频特效/电商一键成片、
  TTS语音合成/声音克隆/音乐生成/文生音效/语音识别(ASR)，或在问"用哪家/哪个模型生成"
  （可灵 kling、即梦 jimeng/Seedream/Seedance、vidu、pixverse、通义万相 aliyun、海螺 minimax、
  sora、veo、gaga、midjourney/mj、gpt-image、nano banana、azure、火山 volcengine、商汤 sensetime）——
  任何此类生成意图或选型问题都用本 skill。即使用户只含糊说"做个视频/出张图/配个音/生成段语音"，
  也应优先用本 skill 把意图翻译成正确的厂商+命令调用。本 skill 负责"选哪家/串什么前置/别踩什么坑"，
  CLI 负责鉴权、轮询、重试、批量、任务注册表。
---

# BlueAI AIGC（图像 / 视频 / 音频，CLI 版）

通过 `blueai-cli` 调用多厂商 AIGC 生成能力。三模态不拆——它们是一条创作链路（图→视频→配音/对口型），强绑定厂商的真正单元是跨模态 pipeline。

## 核心理念

本 skill 是 **blueai-cli 之上的薄选型层**。CLI 是自描述的，所以分工明确：

| 谁负责 | 内容 |
|---|---|
| **本 skill 固化**（人的判断，半年内稳定） | 意图→厂商/模型选型、跨模态前置链路、风险红线、能力边界粗粒度 |
| **委托 CLI 动态查**（会 rot，绝不硬编码） | 精确 model_id 枚举、逐 model 的尺寸/时长/参数约束、字段名/必填项 |
| **CLI 内置接管** | 鉴权、轮询、重试、批量并发、任务注册表 |

> **铁律：怎么调以 spec 为真相。** 任何要调用前，用 `blueai-cli schema <path> --resolve-refs` 拉**当前**参数与 model 枚举，别凭本 skill 或记忆里的 model_id 硬写——厂商版本迭代极快、model_id 内嵌日期戳（如 `doubao-seedance-2-0-260128`），硬编码必过期。

## 第一步永远是：查当前能力

```bash
# 列出某模态所有命令 + 参数摘要 + async/multipart 标志
blueai-cli spec list --path 'aigc.video.**'      # 或 aigc.image.** / aigc.audio.**
blueai-cli spec list --service kling             # 按厂商

# 拉某能力的完整参数 schema——选型定了之后、调用前必做
blueai-cli schema aigc.video.text2video.kling --resolve-refs
```

> **`schema --resolve-refs` 的 `requestBody` 段是参数约束的权威来源,且永远最新。** 里面每个参数都带 `enum`(可选值)、中文 `description`(逐 model 的时长/分辨率/音频/互斥规则)、`default`、`maxLength` 等。例如 kling text2video 的 `model_name` 描述里直接写明每档模型的时长/分辨率/是否支持声音,`duration` 给出 enum `["3"…"15"]` 并注明"非V3模型仅5或10秒"。**选定 model 后务必读这一段,别凭记忆猜参数,也不需要本 skill 替你抄(抄了会过期)。** 注意:顶层 `bodyParams` 是参数名速览(保留 `$ref`)；要看展开后的 enum/描述去读 `requestBody` 段。

**标准调用回路(discover → fill → call),所有 aigc 调用都走这套：**

```bash
# 1) discover：拿当前 model 枚举 + 参数约束
blueai-cli schema aigc.video.text2video.kling --resolve-refs   # 读 requestBody 段
# 2) fill + 预检：先 dry-run 看实际 body，确认参数名/形状对
blueai-cli aigc video text2video kling --params '{"model_name":"kling-v3","prompt":"...","duration":"10","mode":"pro"}' --dry-run
# 3) call：去掉 --dry-run；async 接口默认前台轮询到终态，或加 --async 后台跑
blueai-cli aigc video text2video kling --params '{...}'
```

## 选型：先定模态，再读对应 reference

按用户意图进入对应模态的选型指南（含意图→厂商矩阵 + 前置链路）：

| 模态 | 何时读 | reference |
|---|---|---|
| **视频** | 文/图生视频、首尾帧、数字人、对口型、特效、电商成片、视频翻译/换人 | `references/video.md` |
| **图像** | 文生图、图像编辑（重绘/扩图/去背/转绘）、多图参考、对话式迭代、中文海报 | `references/image.md` |
| **音频** | TTS、声音克隆、音乐/歌词、文生音效、视频生音效、语音识别 ASR | `references/audio.md` |

> reference 给的是**选型结论 + 前置链路**；具体 model_id/参数仍以 `schema` 实时为准。完整研究依据见 `docs/research/2026-06-01-aigc-{video,image,audio}-vendor-report.md`。

## 默认型号快选（用户无特殊偏好 / 不想纠结时）

意图清楚但没点名厂商/型号时，按这套缺省直接钉型号开跑；有特殊诉求（写实摄影、中文帧内出字、像素级 mask 重绘、成本敏感走量）再回对应 reference 细选。

| 场景 | 缺省命令 | 钉死型号 |
|---|---|---|
| 普通出图，无特殊要求 | `blueai-cli aigc image nano-banana-2 llm-relay` | Nano Banana 2（gemini-3.1-flash，快、够用） |
| 要高质量出图 | `blueai-cli aigc image gpt-image-2 llm-relay` | gpt-image-2（OpenAI 旗舰） |
| 生视频，不卡成本 | `blueai-cli aigc video seedance-2-0 <text2video｜image-to-video｜first-last-frame-to-video｜reference-to-video> jimeng` | Seedance 2.0（多模态全能、音画一体） |

> 这些是 `x-cli` 已**钉死 model** 的便捷 leaf——直接出活、不用记内嵌日期戳的 model_id。想换型号仍可在 `--params` 里传 `model` 覆盖，或走通用 leaf（`aigc image gemini-generate / openai-generate llm-relay`、`aigc video text2video jimeng`）自行指定。写实摄影级 / 对话式多轮编辑另有更优解（Nano Banana Pro = `aigc image nano-banana llm-relay`），见 `references/image.md`。

## 端到端示例（拿来改就能跑）

`examples/` 下是真实可跑的命令序列，每个都演示完整链路（discover → 处理前置 → 调用 → 取产物）。遇到对应意图先读对应脚本，照着改 `--params`：

| 意图 | 脚本 |
|---|---|
| 中文文生视频（含 schema 查参 + 轮询取片） | `examples/text2video.sh` |
| 电商短视频带**自己的中文配音**（图→视频→TTS→video-tools 合轨，跨模态全链） | `examples/ecommerce-video-with-voiceover.sh` |
| 中文海报/营销图（文生图） | `examples/text2image-poster.sh` |
| 局部改图（gpt-image-2 multipart edit，已实测） | `examples/image-edit.sh` |
| 数字人口播（图+音频前置） | `examples/digital-human.sh` |
| 声音克隆配音（上传样本→克隆→TTS 三段式） | `examples/voice-clone-tts.sh` |
| 批量出图 + 一次性收口（NDJSON + task wait） | `examples/batch-images.sh` |

## 跨模态前置链路（最易踩坑，调用前必查）

很多生成能力**调用前必须先做一步**。典型模式：

| 模式 | 触发场景 | 链路 |
|---|---|---|
| 公网 URL 输入 | 图生视频/图生图的输入图、视频生音效的视频 | 输入必须是**公网可 GET 的 URL**；本地文件先走 `blueai-cli media-storage file upload` 或厂商上传接口拿 URL/id |
| 上传→引用 | pixverse 图生视频、gaga 图生视频 | 先 upload 拿 `img_id`/`asset_id`，再填进生成接口（pixverse 图走 image/upload、视频走 media/upload，**两类 id 不可混用**） |
| 先建资产 | kling omni 主体引用、指定音色 | 先 `custom-element`/`custom-voice` 拿 `element_id`/`voice_id` 再引用 |
| 先查列表 | minimax 视频 Agent 模板、kling 视频特效 | 先 `*-template-list`/`effect-templates` 拿 `template_id`/`effect_scene` |
| 声音克隆三段式 | minimax/volcengine 克隆音色 | 上传样本→训练/绑定→拿 `voice_id`/`speaker_id` 再 TTS |
| 多步成片 | vidu 电商一键成片 | ad-one-click→查子任务→(可选)edit→compose（compose 的 video_task_ids 数量须==分镜数） |
| 两段式取结果 | veo / sora-get / 任务类 | 提交拿 task_id → 轮询取最终 URL（CLI `--async` 会自动轮询） |
| 本地文件 multipart | llm-relay 音频转录、minimax 声音克隆样本 | `--file ./a.mp3`（相对路径），不支持 URL 直传；transcribe 单文件 ≤25MB |

各模态的具体链路见对应 reference 的「前置依赖」节。

## 关键分叉：用户自带音频 vs 模型自造音画一体

这是跨模态最容易选错的一步，单独拎出来。当任务涉及"视频要有声音/配音/配乐"时，**先判断声音从哪来**：

| 用户诉求 | 正确路径 |
|---|---|
| **用户已有自己的配音文案/音频**（要"我的声音"） | 图生/文生视频模型**无法喂入外部音轨** —— 它们的"音频"是模型自己生成的。正确做法：①(若只有文案)先 `aigc.audio.tts.*` 把文案合成语音 → ②用 `blueai-cli-video-tools` 的 **synthesis 合成**把视频与音轨**合轨** |
| **由模型即兴生成对白/音效/BGM**（不在乎具体内容） | 选音画一体模型一步出（Veo / 可灵 2.6·V3 / 即梦 2.0 / vidu Q3 / 通义万相 2.5+） |
| **给一段已有视频配贴合画面的音效/BGM** | `aigc.audio.video-to-audio.kling`（Kling-Foley，唯一） |
| **要独立的成曲音乐（带词带人声）** | `aigc.audio.music-generation.minimax`（唯一） |

> 记住：**跨模态产物（视频 + 独立生成的音频）的"合轨"不属于 aigc，落在 `blueai-cli-video-tools` 的 synthesis。** aigc 厂商不负责把你的外部音轨并进它生成的视频。

## 风险红线（选型时直接规避）

- **Sora 整线 2026-09-24 官方关停** —— 不建议新选；且 blueai 只暴露收窄版（sora-2、12s、720p，无 Pro/1080p）。
- **流式 TTS 被网关包装成 async 轮询**（minimax/kling/volcengine）—— 真·实时交互场景不能走 CLI，须直连原生接口。
- **水印不可关**：Veo 的 SynthID、Sora 的可见水印+C2PA、Nano Banana 的 SynthID —— 强商用/无水印场景注意。
- **Midjourney 完全无音频能力**（纯图像/视频，且视频无声）—— 任何"用 MJ 配音/配乐/做音效"都不可行，改道 minimax(音乐)/kling(音效)。
- **图硬前置**：Midjourney 视频、GAGA 视频/数字人 —— 没有纯文生视频路径，必须先有图。
- **结果 URL 短时效**：可灵/阿里等结果链接常 24h 过期 —— 拿到立刻转存（可串 `media-storage`）。
- **model 谱碎片化、参数互斥**：kling/aliyun/jimeng 多版本并存、不同版本支持的尺寸/时长/音频开关不同 —— 选定后务必 `schema` 核对该 model 的约束。
- **spec example 过时 ≠ 不可用**：spec 里的 *example* 常钉旧 model（如 OpenAI 图像 example 仍写 `gpt-image-1`，实际现役为 `gpt-image-2`）；而 jimeng/aliyun 的 fast 廉价档则是官方有、网关确实未暴露。一律以 `blueai-cli spec list` / `llm models` 实测为准，别照搬 example、也别假设没暴露。

## 通用调用约定（所有 aigc 命令）

```bash
blueai-cli <aigc 路径> --params '<JSON>' [--async] [--format json|ndjson] [--file <相对路径>] [--api-key <key>]
```

- **响应信封**：`{ok:true,data,meta}` 或 `{ok:false,error:{type,message,hint}}`。业务 payload 常在**双层 data**（`.data.data.xxx`），产物 URL（视频/图片/音频）多在此层，按 `schema` 的响应结构取。
- **异步语义**：大多数生成是 async，CLI **默认前台轮询到终态**（succeeded/failed）才返回；加 `--async` 立即返回 task_id 并写入 `~/.blueai/tasks.json`，后续 `blueai-cli task wait --all` / `task status <id> --watch` 收口。
- **批量**：`--params` 传 JSON 数组即并发跑 N 个；`_label` 回显对账，`_file` 逐项文件。配 `--concurrency N --format ndjson --async` 是 agent 最佳姿势（先全发出去，回头一次性 `task wait --all`）。
- **鉴权**：`--api-key` → 工程级 `.blueai/credentials.json` → `BLUEAI_API_KEY` → `~/.blueai/credentials.json`。auth 失败（exit 3）引导 `blueai-cli config init`。
- **排错**：`--dry-run` 看 body、`--verbose` 看重试；`error.type` 为 validation（参数错，对照 schema）/auth/api（业务错，看 error.detail.body）/network。

## 跨 skill 串联

- 取素材 / 存产物 / 生成分享链接 → `blueai-cli-media-storage`
- 对生成产物做视觉分析/批量打标 → `blueai-cli-datahub`
- 视频后处理（去字幕/超分/切片/合成）→ `blueai-cli-video-tools`
- 选型/能力对比的检索 → 复用 `blueai-cli tools search`（见 search 能力）

## 常见错误

| 错误 | 修正 |
|---|---|
| 凭印象写 model_id | 先 `schema --resolve-refs` 拉当前枚举 |
| 给图生视频传本地文件路径 | 先上传拿公网 URL（media-storage / 厂商 upload 接口） |
| 期望流式实时 TTS 走 CLI | CLI 把流式包装成 async；实时需直连原生 |
| 想给视频配上自己已有的配音/音乐 | 视频模型不吃外部音轨；用 TTS 出语音/选独立音乐 → `blueai-cli-video-tools` synthesis 合轨 |
| 让没有该子能力的厂商干活（MJ 配音、sensetime 出音乐、aliyun-ASR 做 TTS） | 先按 reference 的子能力覆盖表过滤 |
| 拿到 task 还在 processing 就抓产物 URL | 等到 succeeded（默认前台轮询已保证；--async 模式用 task wait） |
| 产物链接过段时间失效 | 24h 时效，立刻转存 |

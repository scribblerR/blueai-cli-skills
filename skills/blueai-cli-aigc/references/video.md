# AIGC 视频选型与前置链路（reference）

> 选型结论稳定，**具体 model_id / 参数约束以 `blueai-cli schema <path> --resolve-refs` 实时为准**。
> 下面提到的旗舰型号（如 kling-v3 系、seedance 2.0 系）只是定位参考，精确字符串、分辨率/时长/音频互斥约束都会随 spec 迭代，**不要硬编码，调用前先查 schema**。
> 成本档为相对档位，最终以 blueai 内部计费为准。覆盖 10 家原生视频厂商。

## 厂商一句话画像

| 厂商 | blueai 路径前缀 | 定位 | 适合场景 |
|---|---|---|---|
| 可灵 Kling | `aigc.video.*.kling` | 国产能力面最全的全栈视频引擎，音画同生+多镜头+原生4K | 高质量中文创作、多镜头叙事、数字人/对口型/特效全流程 |
| 即梦 Jimeng (Seedance) | `aigc.video.*.jimeng` | 字节中文母语模型，成本梯度极宽、音画一体 | 中文电商/短视频量产、多模态参考、性价比走量 |
| Vidu | `aigc.video.*.vidu` | 16s 音视频直出 + 电商一键成片 Agent | 电商/短剧一键成片、参考生视频主体一致性 |
| PixVerse | `aigc.video.*.pixverse` | 性价比+速度标杆，1~15s 任意时长、帧内多语言文字 | 全球化营销批量产线、低成本迭代 |
| 通义万相 Aliyun | `aigc.video.*.aliyun` | 唯一「生成+企业级剪辑/翻译/智能生产」全栈 | 企业级批量剪辑/换人/视频翻译、可编辑视频 |
| 海螺 MiniMax | `aigc.video.*.minimaxi` | 极致物理/微表情、性价比标杆 | 高物理质感图生视频、IP 主体一致性、中文运镜 |
| OpenAI Sora | `aigc.video.*.sora` | 最强原生音画一体+物理一致性，但整线即将关停 | 英文高真实感短片（⚠️ 见风险红线） |
| Google Veo | `aigc.video.*.veo` | prompt 服从度+音画质感第一梯队，原生音频招牌 | 顶级音画一体、对白口型、影视级质感（成本偏高） |
| GAGA (Sand.ai) | `aigc.video.*.gaga` | autoregressive 长序列数字人 | 多语种数字人口播/虚拟主播、长序列身份一致性 |
| Midjourney 悠船 | `aigc.video.*.mj` | MJ 审美承袭的图生视频，氛围强但短/无声/低清 | 美学氛围短片、图→视频抽卡、无音频需求场景 |

> 实际可用路径与子命令以 `blueai-cli spec list` 为准（provider 段总是末尾，因 aigc 路径保留 provider 用于型号/质量/成本比较）。

## 能力边界速查（粗粒度，用于硬过滤）

| 厂商 | 最大时长 | 最高分辨率 | 原生音频 | 图生视频 | 首尾帧 | 多图/参考 | 数字人/对口型 | 中文服从 |
|---|---|---|---|---|---|---|---|---|
| Kling | 15s | 原生4K | ✅(2.6起音画同生) | ✅ | ✅(pro) | ✅多图 1-10 | ✅ avatar+lip-sync | 高(领先) |
| Jimeng | 15s | 1080p | ✅(1.5pro起,2.0双声道) | ✅ | ✅(定长2图) | ✅1-9(2.0) | 部分(口型) | 高(母语) |
| Vidu | 16s | 1080p | ✅(Q3四轨直出) | ✅ | ✅(8s) | ✅参考 1-7 主体 | 部分(声音复刻) | 高(中英日) |
| PixVerse | 15s | 1080p(无4K) | ✅(V5.5起) | ✅ | ✅ | ✅Fusion≤7 | 部分(lipsync) | 中上[推断] |
| Aliyun | 15s | 1080p | ✅(wan2.5起同步) | ✅ | ✅(独立端点) | ✅参考 1-5 | ✅(口播/换人) | 高(母语) |
| MiniMax | 10s(768P)/6s(1080P) | 1080p | ❌需后期合成 | ✅ | ✅(仅02) | ✅主体参考(S2V) | 部分(主体一致) | 高(运镜) |
| Sora | 12s(spec封顶) | 720p(spec两档) | ✅原生同步 | ✅(首帧锚点) | ❌ | character[网关未暴露] | ❌(禁真人) | 英文为主 |
| Veo | 8s(单段) | 1080p/4K(3.1preview) | ✅(招牌) | ✅ | ✅(插帧,Veo3不支持) | ✅参考≤3 | ✅(对白口型) | 顶尖(多语言) |
| GAGA | 60s(avatar)/10s(gaga) | 1080p/720p(avatar) | 素材驱动[非自动配乐] | ✅(图硬前置) | ❌ | ✅(chunks分段) | ✅avatar音频驱动 | 多语种[存疑] |
| MJ 悠船 | ≈21s | 720p(无4K) | ❌无声 | ✅(图硬前置) | ❌ | 4段变体 | ❌ | 中[二手] |

> 矩阵为粗粒度硬过滤用；逐 model 的精确分辨率/时长/宽高比/音频开关互斥约束以 `schema` 为准。

## 按意图选型（首选 + 备选 + 理由 + 风险）

> **没特殊偏好、不卡成本时的缺省**：直接用 **Seedance 2.0**（多模态全能、音画一体）——`x-cli` 已为四个任务钉好便捷 leaf：`aigc video seedance-2-0 <text2video｜image-to-video｜first-last-frame-to-video｜reference-to-video> jimeng`（钉死 `doubao-seedance-2-0-260128`，不用记 model_id）。追**极致画质/原生对白口型**可升级 Veo 3.1 / Kling V3；明确**要走量省钱**回下表细选。下表是按具体诉求细分的更优解。

| 意图 | 首选 | 备选 | 关键风险 |
|---|---|---|---|
| 文生视频·追画质/真实感 | **Veo 3.1**（prompt 服从+物理真实第一梯队，原生音频，最高4K） | Kling V3（原生4K+多镜头）；Sora 2 慎选 | Veo 单段仅 8s、贵、SynthID 不可关；Sora 整线将关停且禁真人/版权 |
| 文生视频·中文/性价比 | **即梦 Seedance**（中文母语，成本梯度极宽，2.0 多模态全能） | 可灵 2.5 Turbo；MiniMax 2.3（物理强但无音频） | 即梦最廉的 pro-fast/2.0-fast 档 **spec 无 model_id 调不到** |
| 图生视频（让一张图动起来） | **MiniMax**（极致物理/微表情，单接口图生，1080p 低成本） | 即梦 image2video；可灵 image2video（运镜/运动笔刷）；Vidu | MiniMax 1080p 仅 6s，要 10s 须降到 768P |
| 首尾帧过渡 | **可灵**（image2video 首尾帧 pro 档成熟） | Vidu start-end(8s)；即梦 first-last-frame；PixVerse transition；Veo 插帧 | 各厂首尾帧多有版本/分辨率约束（如即梦参考模式不支持 1080p）；Veo3 不支持插帧 |
| 原生音频/对白口型一次出 | **Veo 3.1 / Sora 2**（音画一体最强）；中文 **可灵 2.6/V3 或 Vidu Q3** | 即梦 2.0(双声道)；通义万相 wan2.5+ | Sora 即将关停且禁真人；Veo 贵且水印不可关 |
| 数字人口播/对口型 | **GAGA avatar-h1-pro**（音频驱动数字人最长 60s，多语种） | 可灵 avatar+lip-sync；通义 wan2.7-i2v driving_audio；Vidu 声音复刻 | GAGA 商用/水印条款官方零明文；可灵对口型需先有符合条件源视频 |
| 多主体/参考一致性 | **Vidu 参考生视频**（主体库 1-7 主体高一致，电商主体复用） | 可灵 O1/V3 主体库(custom-element)；MiniMax S2V-01；即梦 2.0 参考(1-9)；PixVerse Fusion(≤7) | Vidu q3-mix 不支持主体调用且不支持错峰 |
| 电商/短视频一键成片 | **Vidu 电商一键成片(ad-one-click)**（图→分镜→旁白→BGM→合成一条龙） | 即梦量产；PixVerse（多镜头+音频批量） | ad-one-click 官方字段文档不公开，链路依赖 spec 推断；compose 要求 video_task_ids 数量严格等于分镜数 |
| 长视频/续写延长 | **GAGA avatar(单段 60s)**；通用续写 **可灵 video-extend / 即梦 2.0 延长** | Veo 视频扩展(链式≈148s,工程复杂)；MJ 延长(≈21s)；PixVerse extend | 多数厂商单段仅 8-16s，长片需链式拼接；Sora 官方达120s 但 spec 未暴露 |
| 企业级批量剪辑/换人/翻译 | **通义万相 Aliyun**（唯一全栈：多轨剪辑/字幕级·语音级·面容级翻译/换人/去字幕去图标） | 无强备选 | 前置依赖重（Timeline/模板/媒资ID/OSS，且 OSS region 须与服务地域一致）；wan2.7-r2v/video-edit 双向计费易低估 |

## 前置依赖链路（调用前必做）

| 目标能力 | 前置步骤（必做顺序） | 对应 blueai-cli 命令思路 |
|---|---|---|
| **Vidu 电商一键成片** | ① POST ad-one-click（图→全套子任务）拿主 task_id ② GET ad-one-click/{id}(hidden) 拿子任务 ID 与生成物 ③(可选)edit 改单分镜/旁白/BGM ④(可选)compose 重合成（video_task_ids 数量须==分镜数）。最简：只第①步+轮询主任务 | `aigc.video.*.vidu` 子命令 + `task status --watch`；GET 子任务可能需 raw `api` |
| **Kling 视频延长/对口型** | 先出视频拿 `video_id` 再延长/lip-sync | 先调生成命令，从结果取 video_id |
| **Kling 主体引用(omni)** | 先 `custom-element` 拿 `element_id`，prompt 内用 `<<<element_1>>>` | custom-element 命令 → 主生成命令 |
| **Kling 多模态选区编辑** | 先 init-selection 拿 `session_id`（选区接口 hidden，需 raw API） | `blueai-cli api` 直调选区接口 |
| **Kling 指定音色(2.6)/特效** | 音色：先建/查拿 `voice_id`；特效：先查 `effect_scene` 列表 | 音色/特效列表命令 → 生成命令 |
| **PixVerse 图/视频引用** | **两条上传接口产出不同 id**：图走 `img_id`(image/upload)，视频/音频走 `media_id`(media/upload)，**不可混用**，均 sync 返回。Fusion 用 `@ref_name` 内联；延长可复用平台已生成视频 `source_video_id`(最省) | 先调上传命令拿 id，再喂生成命令 |
| **MiniMax 模板生成** | **video-template-list 是 video-template-generation 的硬前置**（template_id 必填且只能从列表取）；普通 video_generation 无前置可直接调 | template-list 命令 → 模板生成命令 |
| **Veo / Sora 两段式** | Veo：① POST predictLongRunning 拿 task_id ② GET fetchPredictOperation 轮询（多一个 `preparing` 态，网关先转码输入）。Sora remix：先有已完成视频拿 `video_info.id` 再 remix；图生 input_reference 尺寸须与目标 size 完全一致 | 网关已封装为 task_id，用 `--async` + `task status --watch` |
| **Aliyun 企业级** | 剪辑合成**三选一**：Timeline JSON / TemplateId / ProjectId；翻译/智能生产需媒资输入(媒资ID/本账号OSS/公网)，**OSS region 须与服务地域一致**；用模板先查模板名再以 `template` 传入 | 先准备 Timeline/模板/OSS，再调企业级 job 命令 |
| **GAGA asset 体系** | **一套 asset 贯穿音视频**：图/音频都走 `/v1/assets` 上传拿 int64 id；图生视频必须先上传图拿 image id 作 source.content（无纯文生视频）；音频可上传或 `/v1/audios` TTS 现造拿 audio id；avatar 系音频必填 | 上传/TTS 命令拿 id → 生成命令 |
| **Jimeng 输入** | 所有图/视频/音频输入须是**公网可访问 URL**（或 2.0 私域 `asset://`）；网关不接 multipart，参数皆 JSON URL 数组 | `--params` 传 URL 数组，**不用 --file** |
| **MJ 悠船** | 图 →(可选)图任务 id → 视频 → 延长/高清。video-diffusion 两模式二选一(task_id+img_index 或 prompt 内嵌图 URL)；延长/高清吃「视频任务 id + video_index」 | 链式取上一步 id |

**高频通用模式**：(a) 先上传图/视频拿 id 再引用(pixverse/gaga/kling)；(b) 先建主体/音色资产再引用(kling/vidu/minimax)；(c) 先 template-list 拿 template_id(minimax/aliyun/vidu)；(d) 两段式 task_id fetch(veo/sora，网关已封装)；(e) 电商多步成片链路(vidu)。

## 风险红线

- **Sora 整线即将关停**：OpenAI 官方标记 Videos API 与 sora-2/sora-2-pro 全系 deprecated，**计划 2026-09-24 关停**。选型须考虑替代/迁移，禁真人/版权。[Sora]
- **spec 未暴露廉价档**：即梦 `pro-fast`/`2.0-fast`（官方最廉，降价72%）spec 无 model_id；阿里 wan2.7 带日期别名 spec 未暴露。**Agent 调不到最低价档**——以 `spec list` 实时确认当前暴露的 model。[Jimeng/Aliyun]
- **Sora 能力被网关收窄最严重**：spec 仅 `sora-2`（无 Pro）、时长封顶 12s（官方16/20s/扩展120s）、分辨率仅 720p 两档（无1080p）、无 extensions/edits/character/batch。要 1080p/长片走不到。[Sora]
- **强制/不可关水印**：Sora 所有输出带可见动态水印+C2PA；Veo 全部带 SynthID 隐形水印不可关，部分区域强制可见。商用敏感场景注意。[Sora/Veo]
- **无音频需后期合成**：MiniMax 视频生成不带音频、MJ 悠船无声——要音画一体须换厂或后期。[MiniMax/MJ]
- **图硬前置（无纯文生视频）**：GAGA、MJ 均必须先有/上传图，agent 编排步数更多。[GAGA/MJ]
- **结果 URL 短时效，须及时转存**：kling/aliyun ≈24h、vidu origin_url ≈1h。用 blueai media-storage 承接转存。[Kling/Aliyun/Vidu]
- **model 谱碎片化、参数互斥**：kling/aliyun/vidu/pixverse/minimax 按 model 高度碎片化，参数组合错误直接报错（Vidu 9003）。阿里 resolution+ratio vs size 两套参数不可混用、五代模型并存。**逐 model 约束一律查 `schema`**。[全部]
- **双向计费**：阿里 wan2.7-r2v/video-edit 按"输入视频时长+输出时长"双向计费，易低估成本。[Aliyun]
- **条款/合规不透明**：GAGA 对水印/商用/价格零官方明文；MJ 悠船无官方一手视频 API 文档，均依赖网关代理通道稳定性。[GAGA/MJ]

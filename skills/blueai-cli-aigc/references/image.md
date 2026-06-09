# AIGC 图像选型与前置链路（reference）

> 选型结论稳定，**具体 model_id / 尺寸枚举 / 参数约束以 `blueai-cli schema <path> --resolve-refs` 实时为准**（版本号会随上游升级漂移，硬编码必 rot）。

## 模型一句话画像

| 模型/厂商 | blueai 路径前缀 | 定位 | 适合场景 |
|---|---|---|---|
| Midjourney（悠船） | `aigc image * mj` | 美学/艺术质量天花板 + 业界最全编辑套件，控制参数全藏 prompt | 艺术氛围创作、品牌系列出图、全套局部编辑 |
| 即梦 Seedream | `aigc image text2image/image2image jimeng *` | 中文海报/帧内文字渲染顶级 + 最低单价批量生图，但版本谱混乱 | 中文营销物料、批量走量、多图融合 |
| 通义万相 | `aigc image image-generation aliyun` | 原生中文理解最佳 + 单一 messages 入口全能力 | 中文海报/电商带字素材、组图分镜、框选重绘 |
| gpt-image-2（OpenAI，经 relay） | `aigc image gpt-image-2 / openai-generate / openai-edit llm-relay` | 真 multipart mask inpaint + 多参考图，创意/英文强、输入高保真，中文文字偏弱 | 精确 mask 局部重绘、英文创意、多参考图合成 |
| Nano Banana（Gemini，经 relay） | `aigc image nano-banana / nano-banana-2 / gemini-generate llm-relay` | 原生对话式多轮编辑 + photorealism/4K 顶级，强制 SynthID 水印 | 写实摄影级、对话式迭代、多图主体一致 |

> **relay 三个便捷 leaf 钉死了 model**：`gpt-image-2`→`gpt-image-2`；`nano-banana`→`gemini-3-pro-image-preview`（即 Nano Banana Pro，写实/对话式最强）；`nano-banana-2`→`gemini-3.1-flash-image-preview`（更快、日常够用）。通用 leaf（`openai-generate`/`gemini-generate`）需自己在 `--params` 传 `model`。

> **范围说明**：图像生成共 5 个引擎 —— MJ、即梦 Seedream（原生 `jimeng`）、通义万相（原生 `aliyun`）为本体；gpt-image-2 与 Nano Banana 经 `llm-relay` 补充原生树没有的能力。**Qwen-Image 不纳入**（同为阿里、中文出字已由通义万相原生覆盖，relay 重复）；中文帧内文字需求一律选**即梦 / 通义万相**。

## 能力边界速查（粗粒度）

| 模型 | 最高分辨率 | 单次出图 | 文生图 | 图像编辑(重绘/扩图/去背) | 多图参考 | 对话式迭代编辑 | 中文服从 | 帧内文字渲染 | 水印 |
|---|---|---|---|---|---|---|---|---|---|
| MJ | 2048²（v8.1 `--hd`） | 默认 4 | ✅ | ✅ 最全(inpaint/outpaint/pan/remix/retexture/去背)；v8.1 无扩图 | ✅ `--sref`/`--oref`(藏 prompt) | 弱(无原生会话) | 存疑[低可信] | 短文本可、长/小字弱 | EXIF；悠船可见水印存疑 |
| 即梦 Seedream | 4K(4.x)；5.0 spec 仅 2K/3K | 4.x 组图≤15；3.x 单图 | ✅ | ✅ 编辑/组图一体 | ✅ 1–14 张融合 | 弱(消息式非原生) | ★★★★★ | ★★★★★ 中文海报最强 | 布尔 `watermark` / `logo_info` |
| 通义万相 | 4K(仅 pro+文生图+非组图)；编辑/组图 2K | 非组图 1–4；组图 1–12 | ✅ | ✅ 单入口(框选 bbox 重绘；去背靠 prompt) | ✅ 0–9 张 | 弱(切参数非会话) | ★★★★★ | 高级文本渲染 | 布尔 `watermark`(默认 false) |
| gpt-image-2 | 任意满足约束(1024²~4K，如 1536×1024/2048²/3840×2160) | n 1–10 | ✅ | ✅ 真 multipart mask inpaint + 多参考图(无独立去背/扩图) | ✅ 多参考图，**输入高保真不降采样** | 可(Responses 维护会话)非原生 | 英文中上，中文偏弱(中文出字选即梦/万相) | 英文好，中文一般 | 无 SynthID；C2PA 元数据 |
| Nano Banana Pro | 1K/2K/4K | 受 token 上下文限 | ✅ | ✅ 局部编辑/换物体/改光照视角(base64/URL 内联) | ✅ 最多 14 输入图，5 主体一致 | ✅ **原生对话式多轮编辑(核心亮点)** | 强(Gemini 3 Pro) | 英文/短文本顶级；密集中文一般 | **强制 SynthID 不可见水印(不可关)** |

## 按意图选型（首选 + 备选 + 理由 + 风险）

> **没特殊要求时的缺省**：普通出图直接用 **Nano Banana 2**（`aigc image nano-banana-2 llm-relay`，快、够用）；要**高质量**升级 **gpt-image-2**（`aigc image gpt-image-2 llm-relay`）。下表是按具体诉求（写实/中文出字/mask/走量）细分的更优解。

| 意图 | 首选 | 备选 | 风险 |
|---|---|---|---|
| 写实摄影级文生图 | **Nano Banana Pro**(photorealism 顶级 + 4K + 多语言) | MJ v8.1(美学天花板，但参数藏 prompt、长文本弱) | Nano Banana 强制 SynthID 不可关；MJ 悠船是否对齐国际版存疑 |
| 艺术/氛围美学创作 | **MJ v8.1 / Niji7**(艺术风格行业顶级) | Nano Banana Pro | MJ `--ar`/`--sref`/`--oref` 全藏 prompt，易拼错；华纳版权诉讼，受版权角色场景慎用 |
| **中文海报/营销物料(帧内大量中文)** | **即梦 Seedream 4.5**(文字引擎升级，多行/多字体/非拉丁，尤擅中文) | 通义万相 pro(原生中文 + 高级文本 + 4K + 长 prompt) | 即梦"4.0"跨两套接口、版本谱易选错；万相生成图 URL 仅 24h |
| 精确局部重绘/inpaint | **gpt-image-2**(真 multipart mask PNG，像素级，输入高保真) | MJ inpaint/Vary-Region、万相 bbox_list 框选 | gpt-image-2 edit 慢(~1min，x-cli 已设 30min 超时)；MJ 需前置底图 task_id+img_index；万相 bbox 用原图像素坐标须先量图 |
| 扩图/外绘 outpaint | **MJ outpaint / pan**(专用，等比 1.1–2.0 / 单向 1.1–3.0) | — | **MJ v8.1 不支持 outpaint/pan**，须用 v70/v61 旧版；均需前置底图任务；其余厂商无专用外绘端点 |
| 去背景/抠图 | **MJ remove-background**(img_url 直传、单步) | — | 唯一有独立去背端点的是 MJ；其余靠 prompt 编辑近似，效果不保证。**产物是透明底 PNG**——要纯白/其它底色须**本地合成**(如 `magick t.png -background white -flatten out.png`)，**勿再过生成模型**(会改动主体)。本地图须先 media-storage 上传拿 img_url |
| 多图参考·风格/主体一致 | **Nano Banana Pro**(最多 14 输入、跨 5 主体一致) | 即梦 Seedream 4.x(1–14 融合)、gpt-image-2 多参考图、MJ `--oref` | 即梦图生图须 image_urls 公网可访问；MJ `--oref` 2x GPU 且不兼容 Fast/Draft |
| 对话式多轮迭代编辑 | **Nano Banana Pro**(唯一原生：改背景/换物体/调光照/锁主体) | — | 其余厂商均消息式非"对话记忆"原生；Nano Banana 走 native `:generateContent`，响应 base64 内嵌 chat content |
| 批量出图·低成本走量 | **即梦 Seedream 4.0**(0.2 元/张家族最低) | 通义万相快速版 0.2 元/张 | 即梦老版 3.0 t2i 反而 0.259 元/张更贵，勿误选；全 async 须 `--async` + `task wait --all` |

## 前置依赖链路（调用前必做）

调用前**先确认手上素材是本地文件还是公网 URL** —— 四种 edit 范式传图方式完全不同。

| 目标能力 | 前置步骤 | 对应 blueai-cli 命令 |
|---|---|---|
| **MJ 编辑(两步链)** | 8/11 编辑操作(upscale/variation/inpaint/outpaint/pan/remix/edit/enhance)须先出图拿 `task_id` + `img_index` → 再编辑；enhance 额外要求底图为草稿模式产物。控制参数(`--ar`/`--sref`/`--oref`/`--hd`/`--q`/`--draft`)手工拼进 `prompt` 字符串。仅 remove-background/retexture/upload-paint 支持 img_url 直传单步 | `aigc image diffusion mj` → 取 task_id+img_index → `aigc image <edit-op> mj` |
| **gpt-image-2 edit(multipart)** | 准备本地 PNG，可选 mask PNG → 走真 multipart/form-data。官方约束：像素 65.5万–829万、边长 16 倍数、≤3840px、长短边比 ≤3:1。**耗时较长(~1min)，但 x-cli 已为该接口设 30min 超时，无需手动 `--timeout`** | `aigc image openai-edit llm-relay --file <png>` |
| **Nano Banana(base64/URL 内联)** | 备图为 base64 内联或 URL(最多 14 张)，contents 内多 parts 传图；响应 base64 内嵌 chat content | `aigc image gemini-generate llm-relay` |
| **jimeng / 万相(图须公网可访问)** | 图生图/融合须 image_urls 公网可访问(本地图先 media-storage 上传)；jimeng 组图须显式传 `sequential_image_generation:"auto"` + `max_images` 否则只出单图；万相 bbox_list 用原图像素坐标须先量图 | media-storage 上传 → `aigc image image2image jimeng *` / `aigc image image-generation aliyun` |
| **异步执行** | MJ / jimeng / 通义万相**全 async**：提交拿 task_id → 轮询；llm-relay 图像 op(openai/gemini generate+edit)**全 sync 直返**(图像 edit 慢但已配 30min 超时) | async 配合 `--async` + `task wait --all`；sync 直接读返回 |

## 风险红线

- **即梦版本谱混乱(最大陷阱)** — 方舟系(4.0/4.5/5.0，`size=1K/2K/4K`，`watermark` 布尔)与即梦 visual 系(3.0/3.1/4.6/visual_4.0，`width`/`height`/`scale`，`logo_info` JSON)两套参数体系**完全不同、不可混用**。同一营销名"4.0"横跨两条接口(`text2image_v4_0` 方舟 vs `visual_image_v4_0` 即梦 visual 已 hidden)。4.6 是修图垂类版(scale 为整数 [1,100]，区别于 4.0 的 float [0,1])。固定 prompt 跨版本迁移会因 size 枚举不一致踩坑(4.0 有 1K、4.5 无 1K、5.0 是 2K/3K)。**选型前务必 `schema` 确认走哪套接口**。
- **spec example 已过时(非不可用)** — OpenAI 图像 spec 的 *example* 仍钉 `gpt-image-1`(edit example 钉 `dall-e-2`)，但 `llm models` 实测现役是 `gpt-image-2`(最新) + `gpt-image-1.5`。**最省心走钉死 leaf `aigc image gpt-image-2 llm-relay`**；若走通用 `openai-generate` 须手动在 `--params` 指定 `model:"gpt-image-2"`，别用 example 里的旧名。通义万相 spec 仅暴露 `wan2.7-image[-pro]`，历史版 2.6/2.5/2.1 网关未暴露；即梦 5.0 spec size 仅 2K/3K，官方称"2K直出+增强4K"，像素上探约 3072² 而非 4096²。
- **MJ 参数全藏 prompt** — `--ar`/`--sref`/`--oref`/`--hd`/`--q`/`--draft` 等核心控制 spec 均未结构化暴露，须手工拼进 `prompt` 字符串，agent 易错。`Image.width/height` 返回常为 0，不能据返回字段判断尺寸。
- **MJ v8.1 能力缺口** — v8.1 不支持 outpaint/pan/turbo，扩图/延展须降级到 v70/v61 旧版。
- **SynthID 不可关** — Nano Banana Pro 所有输出含 Google SynthID 不可见水印(标准 + Batch API 均带)，部分场景不可关闭。
- **版权风险** — 2025-09 华纳兄弟探索起诉 MJ(超人/史酷比形象侵权)，受版权角色场景慎用；悠船商用/水印条款以小船创意《用户协议》为准、不透明。
- **结果时效** — 通义万相生成图 URL 仅 24h 有效，须及时下载/转存(接 media-storage)；即梦图片结果在 task_status 成功时读 `video_url` 字段(图片任务该字段为 JSON 数组或 URL 字符串，命名易误解)。
- **gpt-image-2 edit 慢但已兜底** — 图像编辑/多参考耗时约 1 分钟(官方上限 ~2min)，x-cli 已为 openai-edit/generate 配 30min 请求超时，无需手动 `--timeout`；输入图按官方约束高保真处理(不再像 gpt-image-1 降采样到 512²)。

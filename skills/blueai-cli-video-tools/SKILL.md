---
name: blueai-cli-video-tools
description: 通过 blueai-cli 调用 BMC 视频处理能力（去字幕 / 去水印 / 去标志 / 去 logo / 视频增强 / 超分 / 提升画质 / 视频切片 / 切片 / 分镜 / 场景检测 / 视频合成 / 合成视频 / 混剪 / 视频工作流）。当用户提到上述任意中文场景词，或英文 erase / remove_logo / enhance / split / synthesis / workflow，甚至只是含糊地说"这个视频帮我处理一下""清理一下视频上的字"——只要意图是把一段网络可访问的视频喂给后端模型并取回处理后的产物，都用此 skill。Skill 负责"挑哪个子命令、参数怎么填、结果在哪取"，CLI 负责轮询、批量、缓存与鉴权——不要再自己写 curl 或 poll 脚本。
---

# blueai-cli-video-tools

这是 BMC 视频能力 API 的 agent 使用手册。所有调用走 `blueai-cli tools video-tools <op>` —— CLI 已经包揽了鉴权、轮询、错误重试、任务注册表、批量并发，本 skill 只解释**子命令选型与参数语义**。

## 子命令选型

| 用户意图 | 子命令 | 必填参数 |
|---------|-------|---------|
| 去字幕 | `erase-subtitles` | `url` |
| 去水印 / 去 logo / 去标志 | `remove-logo` | `url` |
| 提升画质 / 超分 / 增强 | `enhance` | `url` |
| 切片 / 分镜 / 场景检测 | `split` | `url`, `split_type` |
| 视频合成 / 混剪 / 模板拼接 | `synthesis` | `project_template_id`, `task_template_id`, `video_urls`, `material_num_task_need` |
| 工作流（多步流水线） | `workflow` | `template_id`, `user_id` |
| 查询 workflow 步骤详情 | `info` | `task_id` |

`url` 必须**公网可直接 GET** 的视频地址（HTTP 200，无鉴权重定向）。本地文件请先上传到 OSS / 自家 CDN 再传 URL，video-tools 后端不接受 multipart。

## 同步默认 / 异步可选

CLI 默认**前台轮询到终态**才返回。等几十秒到几分钟很正常。完成后输出标准信封：

```json
{"ok": true, "data": {"task_id": 123, "task_status": "TS_SUCCEED", "url": "https://.../result.mp4", ...}, "meta": {...}}
```

`data.url` 就是处理后视频的下载地址（split 任务则是 zip 包含切片+日志）。

如果 agent 想把视频任务和别的工作并行做，加 `--async`：立刻返回 `task_id`，写入 `~/.blueai/tasks.json`。后续随时取：

```bash
# 看现在挂着哪些任务
blueai-cli task list --service video-tools

# 单个守到完成
blueai-cli task status <task_id> --watch

# 等所有挂着的（agent 友好：一次性收口）
blueai-cli task wait --all --format ndjson
```

## 各子命令参数详解

### erase-subtitles —— 去字幕

```bash
blueai-cli tools video-tools erase-subtitles --params '{"url": "https://cdn.example.com/clip.mp4"}'
```

`save_old_info`（可选，默认 0）：
- `0` —— 处理过程中允许重采样到模型偏好分辨率，速度更快
- `1` —— 保留原视频分辨率，输出像素和原始一致；适合后续要做精确剪辑或与原素材对齐时用

### remove-logo —— 去水印 / 去标志 / 去 logo

```bash
blueai-cli tools video-tools remove-logo --params '{"url": "https://cdn.example.com/with_watermark.mp4"}'
```

后端会自动检测画面中的水印/台标/角标位置；不需要人工指定坐标。

### enhance —— 视频超分增强

```bash
blueai-cli tools video-tools enhance --params '{"url": "https://cdn.example.com/lowres.mp4"}'
```

提升分辨率与画面质量。对极低码率或严重压缩的素材效果最明显；本身已经是 4K 的视频意义不大。

### split —— 视频切片

```bash
# 场景检测：按镜头切换分割（少而精，做分镜素材首选）
blueai-cli tools video-tools split --params '{"url": "https://cdn.example.com/long.mp4", "split_type": "scene"}'

# 密集切片：固定时长滑窗切（多而碎，做训练素材或快速浏览）
blueai-cli tools video-tools split --params '{"url": "https://cdn.example.com/long.mp4", "split_type": "cut"}'
```

成功后 `data.url` 是个 zip 包，里面有所有切片视频和切分日志。

### synthesis —— 视频合成

按既定模板，把多段素材拼成一个成片。`video_urls` 是**二元数组的数组**，每项 `[url, shot_type]`，最多 10 项。

```bash
blueai-cli tools video-tools synthesis --params '{
  "project_template_id": 12,
  "task_template_id": 43,
  "video_urls": [
    ["https://cdn.example.com/demo.mp4", "pre"],
    ["https://cdn.example.com/closeup.mp4", "post"]
  ],
  "material_num_task_need": 1,
  "title": "产品介绍",
  "script": ""
}'
```

`shot_type` 枚举：
- `pre` —— 前景素材
- `post` —— 后景素材
- `middle` —— 中间过渡素材
- `sticker` —— 贴纸
- `floating_sticker` —— 浮动贴纸

`material_num_task_need` 是启动合成所需的最少素材数量；填 `0` 表示要等所有素材都上传完才启动。

`project_template_id` / `task_template_id` 由模板维护方提供，skill 无法替你造一个 —— 用户没给就直接问，别瞎填。

### workflow —— 视频工作流

模板化的多步流水线（例如：拉取素材 → 去字幕 → 切片 → 上传）。每个模板有固定步骤，`step_inputs` 用来覆盖某些步骤的默认参数。

```bash
blueai-cli tools video-tools workflow --params '{
  "template_id": 1,
  "user_id": 1,
  "task_name": "周二批处理",
  "step_inputs": [
    {"step": 1, "urls": ["https://cdn.example.com/a.mp4", "https://cdn.example.com/b.mp4"]},
    {"step": 2, "project_id": 1001, "platform": "douyin"}
  ]
}'
```

`step` 从 1 开始；同一对象内的其它键名由模板定义，不是固定的 `urls`/`project_id`。若用户不知道某模板需要哪些 step 参数，让用户先去后台查模板说明再回来。

### info —— 查询 workflow 步骤详情

CLI 内置的 `task status` 只给整体 task_status；如果要看 workflow 每一步的执行情况，用：

```bash
blueai-cli tools video-tools info --params '{"task_id": 80569}'
```

返回 `data.workflow_steps[*]`，每项包含步骤描述、status、output。其它 6 个任务（erase/remove-logo/enhance/split/synthesis/workflow-create 自身的整体状态）用 `blueai-cli task status <task_id>` 就够了，不必走 `info`。

## 批量

任何子命令的 `--params` 都可以传数组，一次性提交 N 个：

```bash
blueai-cli tools video-tools erase-subtitles \
  --params '[
    {"url": "https://cdn.example.com/v1.mp4", "_label": "ep01"},
    {"url": "https://cdn.example.com/v2.mp4", "_label": "ep02"},
    {"url": "https://cdn.example.com/v3.mp4", "_label": "ep03"}
  ]' \
  --concurrency 3 \
  --async \
  --format ndjson
```

`_label` 会原样回到结果里方便对账。批量+`--async` 是 agent 最舒服的姿势：先把活全发出去，去做别的事，最后 `blueai-cli task wait --all --format ndjson` 收果子。

## 鉴权

CLI 用统一的 `apiKey`（与 video-tools 早期文档里的 `appid`/`secret` 不同 —— 网关层会做转换，agent 不需要关心）。鉴权解析顺序：`--api-key` flag → `.blueai/credentials.json`（按 CWD 向上查找）→ `BLUEAI_API_KEY` env → `~/.blueai/credentials.json`。

如果调用返回 `error.type == "auth"`，告诉用户：

> 没配置 BlueAI 凭证。最快的做法：`blueai-cli config init`，按提示粘贴 apiKey；或者临时 `export BLUEAI_API_KEY=...` 再重试。

## 错误处理

CLI 会把 video-tools 后端的 `code != 0` / 401 / 429 / 5xx 全部翻译成统一信封：

```json
{"ok": false, "error": {"type": "api_error|auth|network|validation", "message": "...", "hint": "..."}}
```

429 和 5xx 的临时抖动 CLI 已经会重试（带 Retry-After）。如果最终仍然失败，把 `error.message` 原文给用户看 —— 后端的报错信息（视频太短、URL 不可达、模板不存在等）最有帮助；不要试图自己改写。

## 端到端示例：去水印一条视频

```bash
# 1) 提交并等结果（默认前台轮询）
blueai-cli tools video-tools remove-logo \
  --params '{"url": "https://cdn.example.com/raw_with_logo.mp4"}'

# 2) 从输出里提取 data.url —— 那就是去掉水印后的成品下载地址
```

如果用户希望 agent 不要被卡住：在 `--params` 后加 `--async`，告诉用户 task_id，然后该干别的干别的，回头 `blueai-cli task status <id>` 取结果。

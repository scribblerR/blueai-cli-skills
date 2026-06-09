## blueai-cli-social-data

社媒数据采集 skill — 在 Claude Code 对话里通过自然语言下指令，由 [`blueai-cli`](https://github.com/your-org/blueai_cli) 完成所有 HTTP 调用、轮询、批量并发和任务注册。

> **架构变更（v2.0）**：v1 直接调用 BMC Crawler API 并自带 Python venv；v2 重构为 blueai-cli 的对话编排层，Python 脚本和 venv 全部移除。

---

### 是什么

把"我要采集小红书上 XX 的帖子"、"获取人民日报最近发的文章"等口语化需求，翻译成正确的 `blueai-cli data social <子命令>` 调用，并把返回的 JSON 归档到本地。

支持 **10 种采集场景**，全部映射到 `data social.*` 命令族：

| 场景 | CLI 命令 |
|---|---|
| 关键词搜小红书/抖音/B站/微博帖子（T+1 存量） | `blueai-cli data social batch task` |
| 公众号发文列表 | `blueai-cli data social wp post-list` |
| 公众号文章详情（正文） | `blueai-cli data social wp post-detail` |
| 公众号文章关键词搜索 | `blueai-cli data social wp post-kw-search` |
| 公众号文章评论 | `blueai-cli data social wp post-comment` |
| 视频号账号搜索 | `blueai-cli data social wx video-account-kw-search` |
| 视频号视频列表 | `blueai-cli data social wx video-list` |
| 视频号视频评论 | `blueai-cli data social wx video-comment` |
| 微信搜一搜（搜视频） | `blueai-cli data social wx web-search-videos` |
| 视频下载链接 | `blueai-cli data social wx video-download-url` |

完整字段映射见 `references/modes.json`，CLI 命令示例见 `references/cli_examples.md`。

---

### 前置准备

#### 1. 安装 blueai-cli

```bash
npm install -g blueai-cli
blueai-cli --version
```

#### 2. 配置凭证

```bash
blueai-cli config init    # 交互式：写入 ~/.blueai/credentials.json
```

或单次环境变量：

```bash
export BLUEAI_API_KEY='sk-xxx'
```

或单次命令行：

```bash
blueai-cli data social batch task --api-key 'sk-xxx' --params '...'
```

#### 3. 验证

```bash
blueai-cli doctor       # 检查所有服务连通性
blueai-cli spec --service smcrawler --format ndjson | head -5    # 看 social 命令是否就绪
```

---

### 怎么用

直接在 Claude Code 里用自然语言：

```
帮我搜小红书上最近三个月关于"防晒霜"的帖子，互动量1000以上，按热度排序
```

skill 会：
1. 识别意图为 `stock` 模式
2. 把"小红书"→`media_id=4`，时间→时间戳，"互动量1000以上"→`min_interact_cnt=1000`
3. 渲染**参数确认表**和**命令预览**
4. 用户回 `Y` 后调 `blueai-cli data social batch task --params '{...}'`
5. 自动等到任务完成（status=2），再调 `data social task fetch-data` 拉真实数据
6. JSON 归档到 `~/.claude/blueai-runtime/blueai-cli-social-data/output/stock/<task_id>.json`
7. 渲染 markdown 摘要

#### 各场景示例

| 自然语言 | 触发的 mode |
|---|---|
| "帮我搜小红书上的折叠屏帖子" | `stock` |
| "获取人民日报最近10篇文章" | `realtime_wp` |
| "获取这篇文章的正文：https://mp.weixin.qq.com/s/xxx" | `realtime_wp_detail` |
| "搜索微信上关于AI的文章" | `realtime_wp_kw_search` |
| "抓这篇文章的评论：https://mp.weixin.qq.com/s/xxx" | `realtime_wp_comment` |
| "搜索视频号关于美食探店的账号" | `realtime_wx_channels_kw_search` |
| "获取央视新闻视频号的视频列表" | `realtime_wx_channels_video_list` |
| "这个视频的评论，video_id 是 vid_abc123" | `realtime_wx_channels_video_comment` |
| "微信搜一搜上搜科技视频" | `realtime_wx_channels_video_search` |
| "拿这个视频的下载链接 vid_abc123" | `realtime_wx_channels_video_download` |

---

### 直接用命令行（不通过对话）

skill 是对话编排层，但 CLI 本身可以直接用，参数都是 JSON：

```bash
# 存量数据
blueai-cli data social batch task --params '{
  "keywords": "防晒霜",
  "media_id": 4,
  "start_time": 1767196800,
  "end_time": 1774972799,
  "data_type": 0,
  "min_interact_cnt": 1000,
  "max_data_cnt": 500
}' --format json

# 公众号文章详情
blueai-cli data social wp post-detail --params '{
  "urls": ["https://mp.weixin.qq.com/s/abcdef"],
  "mode": 2
}' --format json

# 拉取任务实际数据（所有 mode 都需要这步）
blueai-cli data social task fetch-data --params '{
  "task_id": "task_abc123",
  "limit": 500
}' --format json > output.json
```

完整示例见 `references/cli_examples.md`。

---

### 数据流

```
用户说 "我要..."
    ↓
[skill] 识别 mode、转换参数 → 渲染确认表
    ↓ (用户 Y)
[skill] 调 blueai-cli data social <子命令> --params '{...}' --format json
    ↓ CLI 自动轮询 statusPath=/api/task/getStatus 到 status=2 (succeeded)
[skill] 提取 task_id
    ↓
[skill] 调 blueai-cli data social task fetch-data --params '{"task_id":"X","limit":500}'
    ↓
JSON 写入 ~/.claude/blueai-runtime/blueai-cli-social-data/output/<mode>/<task_id>.json
    ↓
[skill] 渲染 markdown 摘要（task_id、条数、文件路径、前 3 条预览）
```

---

### 异步 / 批量

CLI 原生支持并发批量：

```bash
blueai-cli data social batch task --params '[
  {"keywords":"防晒霜","media_id":4,"start_time":1767196800,"end_time":1774972799,"_label":"xhs"},
  {"keywords":"防晒霜","media_id":5,"start_time":1767196800,"end_time":1774972799,"_label":"dy"}
]' --concurrency 3 --async --format ndjson
```

`--async` 立刻返回 task_id，agent 可继续做其他事；最后用 `task wait` 收集：

```bash
blueai-cli task wait --all --format ndjson
blueai-cli task list                          # 查注册表
blueai-cli task status task_abc123 --watch    # 单个任务等待
```

任务注册表：`~/.blueai/tasks.json`（CLI 维护，7 天自动清理终态）。

---

### 输出格式

| 格式 | 触发方式 | 用途 |
|---|---|---|
| `json` | 默认 | 完整原始响应，agent 解析或归档 |
| `csv` | `--format csv` | 主要字段平铺，便于在 Excel 打开 |
| `ndjson` | `--format ndjson` | 每行一条，适合大批量流式处理 |
| `table` | `--format table` | 终端友好的 ASCII 表格预览 |

`--format json` 的输出是 `{ok: true, data: ..., meta: {...}}` 的标准 envelope，错误时 `{ok: false, error: {type, message, hint}}`。

---

### 文件位置

```
~/.blueai/
├── credentials.json    # 由 blueai-cli config init 管理
└── tasks.json          # 异步任务注册表（CLI 维护）

~/.claude/blueai-runtime/blueai-cli-social-data/
└── output/
    ├── stock/<task_id>.json
    ├── realtime_wp/<task_id>.json
    └── ...
```

---

### 故障排查

| 现象 | 原因 / 处理 |
|---|---|
| 退出码 3 / "no apiKey found" | 跑 `blueai-cli config init` 或 `export BLUEAI_API_KEY=...` |
| 退出码 4 / 网络超时 | CLI 已自动重试；检查网络或网关 `BLUEAI_SMCRAWLER_GATEWAY` |
| 任务 status=3 | 业务失败，看 `error.detail` 字段；调用 `blueai-cli task status <id>` 看详情 |
| 任务卡在 status=1 超过 5 分钟 | CLI 默认超时 5 分钟；改用 `--async` 提交后用 `task wait` 等更长 |
| `data social task fetch-data` 返回空数组 | 检查 task_id 是否对应已成功的任务（status=2） |

诊断：`blueai-cli doctor`。

---

### 升级 / 迁移

从 v1（自带 Python 脚本）升级到 v2（CLI 编排层）：

| v1 | v2 |
|---|---|
| `python scripts/cli_wrapper.py --mode stock --platform 小红书 ...` | `blueai-cli data social batch task --params '{"media_id":4,...}'` |
| `BASE_DIR/auth/credentials.json` (`secret_key`/`client_id`) | `~/.blueai/credentials.json` (`apiKey`，由 `blueai-cli config init` 写入) |
| `BASE_DIR/tasks/tasks.json` | `~/.blueai/tasks.json`（CLI 维护，schema 不同） |
| Excel 输出 | JSON / CSV 输出（Excel 需要时用 `--format csv` 或拿 JSON 自行转换） |

如有 v1 的 secret_key/client_id：先向数据平台团队申请统一 `apiKey`，再 `blueai-cli config init`。

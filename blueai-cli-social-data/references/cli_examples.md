# CLI 命令示例 — 10 种采集场景

> 本文件给出 10 种场景下完整的 `blueai-cli data social ...` 命令示例。**Step 3 执行前可参考这里。**
>
> 通用约定：
> - `--params` 接受 JSON 字符串（单任务）或 JSON 数组（批量）
> - `--format json`（默认）/ `csv` / `table` / `ndjson`
> - 默认同步模式：CLI 自动轮询到任务终态再返回；加 `--async` 立刻返回 task_id
> - 凭证：`--api-key` > 工程级 `.blueai/credentials.json` > `BLUEAI_API_KEY` 环境变量 > `~/.blueai/credentials.json`

## 1. stock — 关键词搜社媒帖子

```bash
blueai-cli data social batch task --params '{
  "keywords": "防晒霜",
  "media_id": 4,
  "start_time": 1767196800,
  "end_time": 1774972799,
  "data_type": 0,
  "min_interact_cnt": 1000,
  "sort": {"field": "interaction_cnt", "order": "DESC"},
  "max_data_cnt": 500
}' --format json
```

`media_id`：1=微博，4=小红书，5=抖音，7=B站。

## 2. realtime_wp — 公众号发文列表

```bash
blueai-cli data social wp post-list --params '{
  "names": ["人民日报", "新华社"],
  "data_range": 1,
  "start_time": 1767196800,
  "data_type": 2,
  "max_data_cnt": 100
}' --format json
```

`data_range`：1=历史数据，2=今天；`data_type`：1=列表，2=列表+正文。

## 3. realtime_wp_detail — 文章详情

```bash
blueai-cli data social wp post-detail --params '{
  "urls": ["https://mp.weixin.qq.com/s/abcdefg"],
  "mode": 2
}' --format json
```

`mode`：1=带图片标签纯文本，2=纯文字+富文本（默认）。

## 4. realtime_wp_kw_search — 公众号关键词搜索

```bash
blueai-cli data social wp post-kw-search --params '{
  "keywords": "人工智能 大模型",
  "sort_type": 1,
  "period": 30,
  "max_data_cnt": 100
}' --format json
```

`sort_type`：1=按阅读数，2=按时间；`period`：天数 1~720。

## 5. realtime_wp_comment — 文章评论

```bash
blueai-cli data social wp post-comment --params '{
  "urls": ["https://mp.weixin.qq.com/s/abcdefg"],
  "need_post_info": 1,
  "max_data_cnt": 500
}' --format json
```

`need_post_info`：0=只要评论，1=带主帖信息。

## 6. realtime_wx_channels_kw_search — 视频号账号搜索

```bash
blueai-cli data social wx video-account-kw-search --params '{
  "keywords": "美食探店"
}' --format json
```

## 7. realtime_wx_channels_video_list — 视频号视频列表

```bash
blueai-cli data social wx video-list --params '{
  "names": ["央视新闻"],
  "is_download": true,
  "max_data_cnt": 100
}' --format json
```

`is_download`：true=同时返回下载地址。

## 8. realtime_wx_channels_video_comment — 视频评论

```bash
blueai-cli data social wx video-comment --params '{
  "video_ids": ["vid_abc123"],
  "need_post_info": 1
}' --format json
```

## 9. realtime_wx_channels_video_search — 搜一搜搜视频

```bash
blueai-cli data social wx web-search-videos --params '{
  "keyword": "科技",
  "sort_type": 0,
  "publish_time_type": 2,
  "max_data_cnt": 100
}' --format json
```

`sort_type`：0=综合，1=最新，2=最热；`publish_time_type`：0=不限，1=最近1天，2=最近7天，3=最近半年。

## 10. realtime_wx_channels_video_download — 视频下载链接

```bash
blueai-cli data social wx video-download-url --params '{
  "video_ids": ["vid_abc123"]
}' --format json
```

---

## fetch-data — 拉取真实数据（所有 mode 都需要）

create 命令返回的是 `{task_id, status, create_time}`，**不含真实数据**。任务终态后必须再调一次：

```bash
blueai-cli data social task fetch-data --params '{
  "task_id": "task_abc123",
  "limit": 500
}' --format json > output.json
```

`limit` 单次最多 500 条；翻页时把上一次响应里的 `data.scroll_id` 传入下次请求的 `scroll_id` 字段：

```bash
blueai-cli data social task fetch-data --params '{
  "task_id": "task_abc123",
  "scroll_id": "abc...",
  "limit": 500
}' --format json
```

---

## 批量 / 异步组合

提交多个任务同时跑：

```bash
blueai-cli data social batch task --params '[
  {"keywords":"防晒霜","media_id":4,"start_time":1767196800,"end_time":1774972799,"_label":"xhs"},
  {"keywords":"防晒霜","media_id":5,"start_time":1767196800,"end_time":1774972799,"_label":"dy"}
]' --concurrency 3 --async --format ndjson
```

`--async` 立刻返回 task_id，agent 可继续做其他事；后续：

```bash
blueai-cli task wait --all --format ndjson    # 等所有 pending 任务
blueai-cli task list                          # 查看注册表
blueai-cli task status task_abc123 --watch    # 单个任务等待
```

---

## 凭证 / 配置

```bash
# 首次配置
blueai-cli config init    # 交互式写入 ~/.blueai/credentials.json

# 单次覆盖
blueai-cli data social batch task --api-key 'sk-xxx' --params '...'

# 环境变量
export BLUEAI_API_KEY='sk-xxx'

# 切换网关（可选）
export BLUEAI_SMCRAWLER_GATEWAY='https://your-gateway.example.com'
```

诊断：`blueai-cli doctor` 检查所有服务的连通性和凭证状态。

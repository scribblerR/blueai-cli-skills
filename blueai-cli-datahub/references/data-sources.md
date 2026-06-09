# DataHub 数据源配置（CLI 版）

DataHub 支持多种数据源类型。每个 task-create 请求里 `data_source` 必须**且仅能**提供以下三者之一：

| Option | 说明 |
|---|---|
| `data_source_id` | 上传文件返回的 ID（最常用） |
| `data_source_url` | 飞书多维表格链接或下载 URL |
| `data_source_text` | 直接传入 JSON 数据数组 |

外加按类型挑选一个 `*_run_config`：`local_file_run_config` / `bi_run_config` / `connector_run_config` / `db_run_config`。

---

## 1. LocalFileRunConfig — 本地文件

最常用的方式：先 upload-file 拿 `data_source_id`，再创建任务。

### 配置字段
| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `header_row_number` | int | 1 | 表头行号 |
| `sheet_name` | string | 第一个 sheet | Excel 工作表名 |

### 支持的格式
- Excel：`.xlsx`、`.xls`
- CSV：`.csv`
- JSON：`.json`

### 示例：上传 + 创建任务

```bash
# 1. 上传
DS_ID=$(blueai-cli tools ai-batch openapi upload-file \
  --params '{"file_name":"data.xlsx"}' \
  --file ./data.xlsx \
  | jq -r '.data.data.data_source_id')

# 2. 指定 sheet 创建任务
blueai-cli tools ai-batch openapi task-create --params "$(jq -n \
  --arg ds "$DS_ID" '{
    data_source: {
      data_source_id: $ds,
      local_file_run_config: {header_row_number: 1, sheet_name: "数据"}
    },
    prompt: {prompt_text: "请分析：{{内容}}"}
  }')"
```

---

## 2. ConnectorRunConfig — 社交媒体采集

> **注意**：当前 CLI 暴露的 `task-create` 主要用于 LLM 批处理。如果你想做的是"采集小红书/抖音原始数据"，先看下 `blueai-social-media-data` skill — 它专门做采集。
> ConnectorRunConfig 在这里更多用于"采集 + 同步打标"的一体化任务。

### 平台枚举
| MediaTypeEnum | 平台 |
|---|---|
| `MEDIA_TYPE_RED_NOTE` | 小红书 |
| `MEDIA_TYPE_TIKTOK` | 抖音 |
| `MEDIA_TYPE_BILI_BILI` | B 站 |
| `MEDIA_TYPE_WEIBO` | 微博 |
| `MEDIA_TYPE_WEIXIN_PUBLIC_ACCOUNT` | 微信公众号 |
| `MEDIA_TYPE_WEIXIN_VIDEO_ACCOUNT` | 微信视频号 |
| `MEDIA_TYPE_JINGDONG` | 京东 |
| `MEDIA_TYPE_TAOBAO` | 淘宝 |

### 数据类型
| MediaDataTypeEnum | 含义 |
|---|---|
| `MEDIA_DATA_TYPE_POST` | 帖子 |
| `MEDIA_DATA_TYPE_COMMENT` | 评论 |
| `MEDIA_DATA_TYPE_POST_COMMENT_MUST_HAVE_COMMENT` | 帖子+评论（必须有评论） |
| `MEDIA_DATA_TYPE_POST_COMMENT_CAN_NO_COMMENT` | 帖子+评论（可无评论） |
| `MEDIA_DATA_TYPE_POST_LIST` | 帖子列表 |
| `MEDIA_DATA_TYPE_POST_LIST_AND_DETAIL` | 帖子列表+详情 |
| `MEDIA_DATA_TYPE_VIDEO` | 视频 |

### 排序
| MediaSortTypeEnum | 含义 |
|---|---|
| `MEDIA_SORT_TYPE_TIME_DESC` | 时间降序 |
| `MEDIA_SORT_TYPE_INTERACTION_DESC` | 互动量降序 |
| `MEDIA_SORT_TYPE_COMPREHENSIVE` | 综合排序 |
| `MEDIA_SORT_TYPE_LATEST` | 最新 |
| `MEDIA_SORT_TYPE_HOT` | 最热 |

### 示例：采集小红书 + 同步分析情感

```bash
blueai-cli tools ai-batch openapi task-create --params '{
  "name": "小红书美妆情感分析",
  "data_source": {
    "connector_run_config": {
      "media_type": "MEDIA_TYPE_RED_NOTE",
      "data_type": "MEDIA_DATA_TYPE_POST",
      "match_type": "MEDIA_MATCH_TYPE_TITLE",
      "keywords": "美妆+护肤",
      "exclude_keywords": "广告",
      "start_time": "2024-01-01 00:00:00",
      "end_time": "2024-01-31 23:59:59",
      "sort_type": "MEDIA_SORT_TYPE_INTERACTION_DESC",
      "min_interaction": 100,
      "limit": 100
    }
  },
  "prompt": {
    "prompt_text": "分析帖子情感和主题：{{content}}\n返回 JSON：{\"sentiment\":\"\",\"topic\":\"\",\"key_products\":[]}",
    "prompt_run_config": {"require_llm_result_json": true}
  }
}'
```

### 关键词语法
- `+` 表示且关系：`美妆+护肤` = 同时含两个词
- `|` 表示或关系：`美妆|护肤` = 含任一个词

---

## 3. DBRunConfig — 数据库

从 MySQL 读数据需要先在 DataHub 后台配好数据库连接，拿到 `data_source_id`。

### 字段
| 字段 | 必填 | 说明 |
|---|---|---|
| `sql` | 是 | 完整 SELECT 或 WHERE 子句 |
| `table_name` | 否 | 给了就当 WHERE 用，不给就当完整 SQL |
| `primary_key` | 否 | 主键字段名（用于分页） |

### 完整 SQL 模式
```bash
blueai-cli tools ai-batch openapi task-create --params '{
  "data_source": {
    "data_source_id": "db-xxx",
    "db_run_config": {
      "sql": "SELECT id, name, content FROM articles WHERE status='\''published'\'' LIMIT 100"
    }
  },
  "prompt": {"prompt_text": "分析：{{content}}"}
}'
```

### WHERE 子句模式
```bash
blueai-cli tools ai-batch openapi task-create --params '{
  "data_source": {
    "data_source_id": "db-xxx",
    "db_run_config": {
      "table_name": "articles",
      "primary_key": "id",
      "sql": "status = \"published\" AND created_at > \"2024-01-01\""
    }
  },
  "prompt": {"prompt_text": "分析：{{content}}"}
}'
```

---

## 4. BIRunConfig — 飞书多维表格

直接读飞书多维表格的数据，**还能把 LLM 结果回写到指定列**——这是飞书集成的杀手锏。

### 字段
| 字段 | 必填 | 说明 |
|---|---|---|
| `app_token` | 是 | 飞书多维表格 App Token |
| `table_id` | 是 | 表格 ID |
| `view_id` | 否 | 视图 ID（不传读全表） |
| `write_back_map` | 否 | 回写映射列表 |

### Write Back Map
把 LLM 返回的 JSON 字段映射到飞书表的列：
- `json_result_key` — LLM JSON 里的 key
- `bi_column_name` — 飞书表的列名

### 示例：分析 + 回写

```bash
blueai-cli tools ai-batch openapi task-create --params '{
  "name": "飞书表格情感分析",
  "data_source": {
    "data_source_url": "https://bluefocus.feishu.cn/wiki/xxx?table=tblxxx&view=vewxxx",
    "bi_run_config": {
      "app_token": "xxx",
      "table_id": "tblxxx",
      "view_id": "vewxxx",
      "write_back_map": [
        {"json_result_key": "sentiment", "bi_column_name": "情感分析"},
        {"json_result_key": "summary", "bi_column_name": "内容摘要"}
      ]
    }
  },
  "prompt": {
    "prompt_text": "分析内容：{{内容}}\n返回 JSON：{\"sentiment\":\"\",\"summary\":\"\"}",
    "prompt_run_config": {"require_llm_result_json": true}
  }
}'
```

> 飞书表里得有"情感分析"、"内容摘要"列，不然回写会失败。
> `data_source_url` 应该是表格 URL，里面带 `?table=...&view=...`；`bi_run_config` 里再写一遍 token/id 是冗余但 API 要求的。

---

## 5. data_source_text — 直接传入 JSON 数据

适合数据量小（< 几十条）、不想专门上传文件的场景。

```bash
blueai-cli tools ai-batch openapi task-create --params '{
  "data_source": {
    "data_source_text": [
      {"id": 1, "text": "这是一条正面评论"},
      {"id": 2, "text": "这是一条负面评论"},
      {"id": 3, "text": "这是一条中性评论"}
    ]
  },
  "prompt": {"prompt_text": "分析情感：{{text}}"}
}'
```

也很适合 Media Storage 单文件视觉分析：
```bash
blueai-cli tools ai-batch openapi task-create --params '{
  "data_source": {
    "data_source_text": [{"url": "https://cdn.example.com/video.mp4"}]
  },
  "prompt": {
    "prompt_type": "PROMPT_TYPE_VISION",
    "prompt_text": "分析视频内容",
    "prompt_run_config": {"vision_fields_names": ["url"]}
  },
  "model": {"model_id": "gpt-4o"}
}'
```

---

## 选哪个？快速决策

| 场景 | 用什么 |
|---|---|
| 我有本地 CSV/Excel/JSON | LocalFile（先 upload-file） |
| 我要采集小红书/抖音再标注 | Connector，或者先用 `blueai-social-media-data` 采，再回到 LocalFile |
| 我数据在 MySQL | DB（要先在后台配数据库连接） |
| 我数据在飞书多维表，结果想回写表里 | BI |
| 我就几条数据/几个 URL | data_source_text |

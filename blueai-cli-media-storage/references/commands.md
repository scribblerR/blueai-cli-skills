# Commands Reference

`blueai-cli media-storage` 子命令完整参数说明。所有命令都接受 SKILL.md 中描述的通用 flag（`--params` / `--format` / `--dry-run` / `--verbose` / `--api-key` / `--concurrency` / `--fail-fast` / `--async`），下文只列出每个命令的业务参数（即 `--params` 内的 JSON 字段）。

> 所有响应外层都包裹 CLI 信封 `{ok, data, meta}`；下文 "Response" 一栏指 `data`（即后端原始 body）的形状。

---

## upload

### `upload create`

POST `/v1/tasks/upload` · sync

创建一个媒体上传任务（从 `BAIDU_PAN` / `PUBLIC_URL` / `INTERNAL_OS` 抓取到目标对象存储）。

**Params:**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `source_type` | enum | ✅ | `BAIDU_PAN` \| `PUBLIC_URL` \| `INTERNAL_OS` \| `LOCAL_FILE` |
| `object_list` | `MediaObject[]` | ✅ | 见下方 MediaObject |
| `target_storage` | enum[] |  | `COS` / `OSS` / `TOS` / `GCP`（不支持 `BOS`），有 `use_case` 时可省 |
| `task_name` | string |  | 留空自动生成 |
| `user_email` | string[] |  | 可见用户邮箱列表 |
| `object_acl` | string |  | `private` / `public-read` |
| `use_case` | string[] |  | 场景：`google` / `blueai` / `dify` |
| `is_sync_nas` | bool |  | 是否同步到 NAS |
| `nas_group_id` | string |  | NAS 分组 |
| `is_notify` | bool |  | 是否飞书通知 |

**MediaObject:**

| 字段 | 适用 source_type | 说明 |
|------|------------------|------|
| `url` | 全部 | 链接地址 |
| `vcode` | `BAIDU_PAN` | 提取码 |
| `os_type` | `INTERNAL_OS` | 源对象存储类型 `COS`/`OSS`/`TOS`/`BOS`/`GCP` |
| `bucket` | `INTERNAL_OS` | 桶名 |
| `region` | `INTERNAL_OS` | 区域 |
| `object_keys` | `INTERNAL_OS` | object key 列表 |
| `url_type` | `PUBLIC_URL` | `0`=下载链接，`1`=详情页链接 |
| `platform` | `PUBLIC_URL` | `xhs` / `bilibili` / `dy` / `tiktok` / `youtube` |
| `media_author` |  | 可选作者标记 |
| `media_name` |  | 可选自定义名称 |

**Response (`data`):** `{ code, message, data: { task_id } }`

---

### `upload result`

GET `/v1/tasks/upload/{task_id}` · sync

**Params:**

| 字段 | 必填 | 说明 |
|------|------|------|
| `task_id` | ✅ | 上传任务 ID（来自 `upload create`） |
| `page_num` |  | 1-based，默认 1 |
| `page_size` |  | 默认 10 |

**Response (`data.data`):**
```
{
  task_id, task_name, status, progress,
  source_type, target_storage[],
  results: [{ media_id, media_name, media_type, media_status,
              file_size, file_ext, origin_url, file_path,
              object_storage_result: [{ storage, bucket, key, url,
                                        preview_url, video_play_url,
                                        gcp_url, cover_url, expired }] }],
  page_size, page_num, total_count,
  channel, use_case, created_email
}
```

`status` 终态：`COMPLETED` / `FAILED` / `PARTIAL_SUCCESS`。

---

## share

### `share create`

POST `/v1/tasks/share` · sync

`task_ids` / `media_ids` / `url_list` **至少传一个**，可组合。

**Params:**

| 字段 | 类型 | 说明 |
|------|------|------|
| `task_ids` | string[] | 上传任务 ID 列表 |
| `media_ids` | string[] | 媒体 ID 列表 |
| `url_list` | string[] | 公网 URL 列表 |
| `task_name` | string | 分享任务名 |
| `pkg_zip` | bool | 是否打包成 zip |
| `period` | int | 有效期天数（默认 7） |
| `remark` | string | 分享备注 |
| `user_email` | string[] | 可见用户邮箱 |
| `is_notify` | bool | 飞书通知 |

**Response:** `{ code, message, data: { share_task_id } }`

### `share result`

GET `/v1/tasks/share/{share_task_id}` · sync

**Params:** `{ share_task_id }`

**Response (`data.data`):** `{ share_task_id, share_task_name, status, progress, short_url, link, period, pwd, remark, created_email }`

---

## package

### `package create`

POST `/v1/tasks/package` · sync — 把多个媒体合并打包为 zip。

**Params:**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `url_list` | string[] | ✅ | 待打包的媒体 URL |
| `task_name` | string |  |  |
| `user_email` | string[] |  |  |
| `is_notify` | bool |  |  |

**Response:** `{ code, message, data: { task_id } }`

### `package result`

GET `/v1/tasks/package/{task_id}` · sync

**Params:** `{ task_id }`

**Response (`data.data`):** `{ task_id, task_name, file_total_size, file_total_count, progress, status, created_at, updated_at, created_by, expired_at, period, download_urls[], channel, remark }`

---

## media

### `media info`

GET `/v1/media/info` · sync — 批量按 `media_id` 查媒体详情。

**Params:**

| 字段 | 类型 | 必填 |
|------|------|------|
| `media_id` | string[] | ✅ |

**Response (`data.data`):** array of `{ media_id, media_name, media_type, media_status, file_size, file_ext, origin_url, file_path, object_storage_result[] }`

---

## scene

### `scene media-list`

GET `/v1/scene/media_list` · sync — 仅授权 API Key 可用。

**Params:**

| 字段 | 必填 | 说明 |
|------|------|------|
| `start_time` | ✅ | Unix 秒时间戳 |
| `end_time` |  | 默认当前时间 |
| `scene` |  | `google` / `blueai` / `dify`，可多选 |
| `user_email` |  | string[] |
| `task_id` |  |  |
| `page_num` |  | 默认 1 |
| `page_size` |  | 默认 200，上限 1000 |

**Response (`data.data`):** `{ total_count, has_more, page_num, page_size, result: [{ media_id, media_name, media_type, file_size, file_ext, origin_url, object_storage_result[] }] }`

### `scene task-list`

GET `/v1/scene/task_list` · sync — 仅授权 API Key 可用。

**Params:** 同 `scene media-list`，但 `page_size` 默认 20，上限 100；不支持 `task_id` 过滤。

**Response (`data.data`):** `{ total_count, has_more, page_num, page_size, result: [{ task_id, task_name, task_type, task_status, progress, created_at, total_file_cnt, total_file_size, created_email, media_list[] }] }`

---

## file

### `file upload`

POST `/v1/file/upload` · sync · multipart

通过 HTTP 流式 multipart 上传本地文件。**`file_size` 必须由调用方算好写进 `--params`**，CLI 不会自动补全。

**通用 flag**: `--file <relative-path>`（**必须**），`--params '{"file_size": <bytes>}'`（必须包含 file_size）

**Params (写入 query):**

| 字段 | 必填 | 说明 |
|------|------|------|
| `file_size` | ✅ | 文件字节数，调用方先 `wc -c < file` 或等价方式取得 |
| `file_name` |  | 自定义文件名（覆盖文件本身的 basename） |

**单文件示例：**
```bash
SIZE=$(wc -c < ./video.mp4)
blueai-cli media-storage file upload --file ./video.mp4 --params "{\"file_size\":$SIZE}"
```

**批量上传：** `--params` 改成数组，每项加 `_file: "<相对路径>"` 与对应的 `file_size`：
```bash
SIZE_A=$(wc -c < ./a.jpg); SIZE_B=$(wc -c < ./b.mp4)
blueai-cli media-storage file upload --params "[
  {\"_file\":\"./a.jpg\",\"file_size\":$SIZE_A},
  {\"_file\":\"./b.mp4\",\"file_size\":$SIZE_B}
]" --concurrency 3 --format ndjson
```
注意：批量场景下不能再用全局 `--file`。

**Response (`data.data`):** `{ file_url }`

**注意**：上传到 COS 立即返回；如果服务端配置同步到 GCP/BOS 等其他存储，需用响应中的 `task_id`（如有）调 `upload result` 轮询拿到全部链接。

---

## 错误码（API 端）

CLI 把后端 `code != 0` 统一转换为 `{"ok": false, "error": {"type": "api", "detail": {...}}}`。常见 `code`：

| code | HTTP | 含义 |
|------|------|------|
| `0` | 200 | 成功 |
| `1003` | 401 | API Key 无效 |
| `9001` | 400 | 请求参数错误 |
| `2000` | 404 | 资源不存在 |
| `9099` | 500 | 内部错误（CLI 已自动重试 2 次仍失败） |

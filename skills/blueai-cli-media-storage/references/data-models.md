# Data Models

## 枚举

### SourceType — 上传任务源

| 值 | 含义 |
|----|------|
| `BAIDU_PAN` | 百度网盘分享链接（需 `vcode`） |
| `PUBLIC_URL` | 公网可下载链接 |
| `INTERNAL_OS` | 内部对象存储（需 `os_type` / `bucket` / `region` / `object_keys`） |
| `LOCAL_FILE` | 本地文件（通常通过 `file upload` 走 multipart） |

### StorageType — 对象存储

| 值 | 厂商 |
|----|------|
| `COS` | 腾讯云 |
| `OSS` | 阿里云 |
| `TOS` | 火山云 |
| `BOS` | 百度云 |
| `GCP` | Google Cloud Storage |

> ⚠️ **upload 任务的 `target_storage` 不接受 `BOS`**；media-info / scene 等查询接口可以返回 BOS 结果。

### TaskStatus — 任务状态

| 值 | 含义 | 终态？ |
|----|------|--------|
| `PENDING` | 等待调度 | 否 |
| `PREPARING` | 准备中 | 否 |
| `PROCESSING` | 执行中 | 否 |
| `COMPLETED` | 完成 | ✅ |
| `FAILED` | 失败 | ✅ |
| `PARTIAL_SUCCESS` | 部分成功 | ✅ |
| `EXPIRED` | 已过期 | ✅ |
| `ALL` | 仅查询过滤用 | — |

### MediaStatus — 媒体状态

`PENDING` / `PROCESSING` / `COMPLETED` / `FAILED`（终态：后两者）

### MediaType

`VIDEO` / `AUDIO` / `IMAGE` / `FILE` / `DOCUMENT` / `ARCHIVE` / `FONT` / `CODE`

### TaskType

`UNKNOWN` / `UPLOAD` / `SHARE`

### Scene — 场景

`google` / `blueai` / `dify`

### Platform — 媒体来源平台（仅 PUBLIC_URL）

`xhs`（小红书）/ `bilibili` / `dy`（抖音）/ `tiktok` / `youtube`

### ObjectAcl

`private` / `public-read`

### Channel — 创建渠道（响应字段）

`WEB` / `OPENAPI` / `CHROME_EXTENSION`

---

## 请求模型

### `MediaObject`（`upload create.object_list[]`）

```ts
{
  url?: string;
  vcode?: string;            // BAIDU_PAN 必填
  os_type?: StorageType;     // INTERNAL_OS 用
  bucket?: string;           // INTERNAL_OS 用
  region?: string;           // INTERNAL_OS 用
  object_keys?: string[];    // INTERNAL_OS 用
  url_type?: 0 | 1;          // PUBLIC_URL: 0=下载链接, 1=详情页
  platform?: Platform;       // PUBLIC_URL: 来源平台
  media_author?: string;
  media_name?: string;
}
```

### `CreateUploadTaskRequest`

```ts
{
  task_name?: string;
  source_type: SourceType;            // 必填
  object_list: MediaObject[];         // 必填
  target_storage?: StorageType[];     // 不含 BOS
  user_email?: string[];
  object_acl?: ObjectAcl;
  use_case?: Scene[];
  is_sync_nas?: boolean;
  nas_group_id?: string;
  is_notify?: boolean;
}
```

### `CreateShareTaskRequest`

```ts
{
  task_name?: string;
  task_ids?: string[];        // 三选一/可组合
  media_ids?: string[];
  url_list?: string[];
  pkg_zip?: boolean;
  period?: number;            // 有效期天数，默认 7
  remark?: string;
  user_email?: string[];
  is_notify?: boolean;
}
```

### `CreatePackageTaskForOpenApiRequest`

```ts
{
  url_list: string[];         // 必填
  task_name?: string;
  user_email?: string[];
  is_notify?: boolean;
}
```

---

## 响应模型

### `ObjectStorageResult`

每个媒体在每个目标存储中的结果：

```ts
{
  storage: StorageType;
  bucket: string;
  key: string;                // 对象 key
  etag: string;
  url: string;                // 临时访问链接
  expired: number;            // 链接有效秒数
  preview_url: string;        // 预览 CDN
  video_play_url?: string;    // 视频播放
  cover_url?: string;         // 视频封面
  gcp_url?: string;           // gs:// 协议链接（仅 GCP）
}
```

### `MediaResult` / `MediaInfo`

```ts
{
  media_id: string;
  media_name: string;
  media_type: MediaType;
  media_status: MediaStatus;
  file_size: string;          // 注意：API 返回字符串
  file_ext: string;
  origin_url?: string;        // PUBLIC_URL 时
  file_path?: string;
  object_storage_result: ObjectStorageResult[];
}
```

### `UploadTaskResult` (`upload result.data.data`)

```ts
{
  task_id: string;
  task_name: string;
  status: TaskStatus;
  progress: number;           // 0-100
  source_type: SourceType;
  target_storage: StorageType[];
  results: MediaResult[];
  page_size: number;
  page_num: number;
  total_count: number;
  channel: Channel;
  use_case: Scene[];
  created_email: string;
}
```

### `ShareTaskResult` (`share result.data.data`)

```ts
{
  share_task_id: string;
  share_task_name: string;
  status: TaskStatus;
  progress: number;
  short_url: string;          // 短链
  link: string;               // 完整分享链接
  period: number;
  pwd: string;                // 提取码
  remark: string;
  created_email: string;
}
```

### `PackageInfo` (`package result.data.data`)

```ts
{
  task_id: string;
  task_name: string;
  file_total_size: string;
  file_total_count: number;
  progress: number;
  status: string;
  created_at: string;
  updated_at: string;
  expired_at: string;
  period: number;
  created_by: string;
  download_urls: string[];
  channel: Channel;
  remark: string;
}
```

### `TaskResultItem` (`scene task-list.data.data.result[]`)

```ts
{
  task_id: string;
  task_name: string;
  task_type: TaskType;
  task_status: TaskStatus;
  progress: number;
  created_at: string;
  total_file_cnt: string;
  total_file_size: string;
  created_email: string;
  media_list: MediaResult[];
}
```

---

## 大小与分页约束

| 接口 | 字段 | 默认 | 上限 |
|------|------|------|------|
| `upload result` | `page_size` | 10 | (无明确上限，建议 ≤200) |
| `scene media-list` | `page_size` | 200 | 1000 |
| `scene task-list` | `page_size` | 20 | 100 |
| `upload create` | 单任务总量 | — | 100 GB |
| `file upload` | 一次 multipart 文件数 | — | 300 |

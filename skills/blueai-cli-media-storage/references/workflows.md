# Workflows

实际场景下的端到端 CLI 调用模板。所有响应都假设 CLI 信封为 `{ok: true, data: <api-body>}`，因此后端的业务 payload 路径是 `data.data`。

---

## 1. 百度网盘 → 云存储

**输入**：百度盘分享链接 + 提取码
**输出**：媒体在 COS（可叠加 OSS / TOS / GCP）的临时访问链接

```bash
# Step 1: 创建任务
RESP=$(blueai-cli media-storage upload create --params '{
  "source_type": "BAIDU_PAN",
  "object_list": [
    {"url": "https://pan.baidu.com/s/1xxxxx", "vcode": "abc1"}
  ],
  "target_storage": ["COS"],
  "task_name": "baidu-sync-demo"
}')
TASK_ID=$(echo "$RESP" | jq -r '.data.data.task_id')

# Step 2: 轮询
while :; do
  R=$(blueai-cli media-storage upload result --params "{\"task_id\":\"$TASK_ID\"}")
  S=$(echo "$R" | jq -r '.data.data.status')
  echo "status=$S progress=$(echo "$R" | jq -r '.data.data.progress')%"
  case "$S" in
    COMPLETED|FAILED|PARTIAL_SUCCESS) break ;;
  esac
  sleep 5
done

# Step 3: 取链接
echo "$R" | jq '.data.data.results[] | {media_name, urls: [.object_storage_result[].url]}'
```

**多文件**：`object_list` 直接放多条 `{url, vcode}` 即可，一次任务最多 100 GB。

**多目标存储**：`target_storage: ["COS","OSS","GCP"]`，结果中 `object_storage_result[]` 会按存储分别返回链接。

---

## 2. 公网 URL 批量入库

`--params` 传数组就触发 CLI 内置批量并发；用 `--format ndjson` 流式拿每条结果。

```bash
blueai-cli media-storage upload create --params '[
  {"source_type":"PUBLIC_URL","object_list":[{"url":"https://a.com/1.mp4","platform":"bilibili"}],"target_storage":["COS"],"_label":"v1"},
  {"source_type":"PUBLIC_URL","object_list":[{"url":"https://a.com/2.mp4","platform":"bilibili"}],"target_storage":["COS"],"_label":"v2"},
  {"source_type":"PUBLIC_URL","object_list":[{"url":"https://a.com/3.mp4","platform":"bilibili"}],"target_storage":["COS"],"_label":"v3"}
]' --concurrency 3 --format ndjson > task-ids.ndjson
```

输出（每行一条）：
```json
{"index":0,"label":"v1","ok":true,"data":{"code":0,"data":{"task_id":"t-001"}},"serviceId":"media-storage"}
{"index":1,"label":"v2","ok":true,"data":{"code":0,"data":{"task_id":"t-002"}},"serviceId":"media-storage"}
...
{"batch_summary":{"total":3,"succeeded":3,"failed":0}}
```

之后再批量轮询：
```bash
TASK_IDS=$(jq -rs 'map(select(.batch_summary|not) | .data.data.task_id)' < task-ids.ndjson)
# 把 task_ids 喂给 upload result 的批量调用
PARAMS=$(echo "$TASK_IDS" | jq 'map({task_id: .})')
blueai-cli media-storage upload result --params "$PARAMS" --concurrency 3 --format ndjson
```

> `_label` 是 CLI 批量模式下的关联标签，会被自动剥离不发给后端，仅原样回写在结果里方便对账。

---

## 3. 本地文件流式上传

### 单文件

```bash
# 必须在文件所在目录或父目录运行，--file 仅接受相对路径
# file_size 必须由调用方先算好（CLI 不自动补全）
cd /path/to/work
SIZE=$(wc -c < ./video.mp4)
blueai-cli media-storage file upload --file ./video.mp4 --params "{\"file_size\":$SIZE}"
```

`Content-Length` 由 CLI 预先计算（不使用 `Transfer-Encoding: chunked`，兼容拒绝 chunked 的网关）。但 query 中的 `file_size` 后端要求显式传入，必须由调用方写入 `--params`。

响应：
```json
{ "ok": true, "data": { "code": 0, "data": { "file_url": "https://cos.../video.mp4" } } }
```

### 自定义文件名

```bash
SIZE=$(wc -c < ./tmp.mp4)
blueai-cli media-storage file upload \
  --file ./tmp.mp4 \
  --params "{\"file_size\":$SIZE,\"file_name\":\"final-cut-v2.mp4\"}"
```

### 批量上传（同时上传多个本地文件）

```bash
cd /workspace
SA=$(wc -c < ./pic-a.jpg); SB=$(wc -c < ./pic-b.png); SC=$(wc -c < ./pic-c.webp)
blueai-cli media-storage file upload --params "[
  {\"_file\":\"./pic-a.jpg\",\"file_size\":$SA},
  {\"_file\":\"./pic-b.png\",\"file_size\":$SB},
  {\"_file\":\"./pic-c.webp\",\"file_size\":$SC}
]" --concurrency 3 --format ndjson
```

注意：`_file` 与全局 `--file` **不能同时使用**；批量模式下每项必须自带 `_file` 与对应的 `file_size`。

---

## 4. 创建分享链接（生成百度网盘短链）

```bash
# 直接基于已完成的上传任务分享
SHARE_RESP=$(blueai-cli media-storage share create --params '{
  "task_ids": ["t-001", "t-002"],
  "period": 7,
  "remark": "客户审片"
}')
SHARE_ID=$(echo "$SHARE_RESP" | jq -r '.data.data.share_task_id')

# 轮询拿短链
while :; do
  R=$(blueai-cli media-storage share result --params "{\"share_task_id\":\"$SHARE_ID\"}")
  S=$(echo "$R" | jq -r '.data.data.status')
  case "$S" in
    COMPLETED|FAILED|PARTIAL_SUCCESS) break ;;
  esac
  sleep 5
done

echo "$R" | jq '.data.data | {short_url, link, pwd, period}'
```

**变体**：
- 按 `media_ids` 分享：`{"media_ids":["m-1","m-2"], "period":3}`
- 按公网 URL 分享：`{"url_list":["https://...mp4"], "pkg_zip":true}` —— 当 `pkg_zip:true` 时打成 zip 包
- 三类来源可以混用，只要至少传一个

---

## 5. 按 media_id 批量查媒体详情

```bash
blueai-cli media-storage media info --params '{
  "media_id": ["m-001", "m-002", "m-003"]
}' --format json | jq '.data.data[] | {media_id, media_name, status: .media_status, urls: [.object_storage_result[].url]}'
```

---

## 6. 按场景检索历史媒体 / 任务

仅授权 API Key 可见。常用于做对账或导出。

```bash
# 最近 30 天 blueai 场景所有上传完成的媒体
START=$(date -d '30 days ago' +%s)
blueai-cli media-storage scene media-list --params "{
  \"scene\":[\"blueai\"],
  \"start_time\":$START,
  \"page_size\":1000
}" --format json | jq '.data.data | {total: .total_count, has_more, count: (.result|length)}'
```

```bash
# 同一时间段内所有 SHARE 任务，导出为 CSV
START=$(date -d '7 days ago' +%s)
blueai-cli media-storage scene task-list --params "{
  \"scene\":[\"blueai\"],
  \"start_time\":$START,
  \"page_size\":100
}" --format csv > tasks.csv
```

**分页**：当 `data.data.has_more=true` 时，递增 `page_num` 继续拉。

---

## 7. 打包多媒体生成 zip 下载链接

```bash
# Step 1: 创建打包任务
PKG=$(blueai-cli media-storage package create --params '{
  "url_list": [
    "https://cos.../a.mp4",
    "https://cos.../b.mp4",
    "https://cos.../c.png"
  ],
  "task_name": "weekly-bundle"
}')
PKG_ID=$(echo "$PKG" | jq -r '.data.data.task_id')

# Step 2: 轮询 & 取下载链接
while :; do
  R=$(blueai-cli media-storage package result --params "{\"task_id\":\"$PKG_ID\"}")
  S=$(echo "$R" | jq -r '.data.data.status')
  case "$S" in
    COMPLETED|FAILED|PARTIAL_SUCCESS) break ;;
  esac
  sleep 5
done

echo "$R" | jq '.data.data | {progress, status, urls: .download_urls, expired_at}'
```

---

## 8. 排错时常用的"先 dry-run 再真发"

不确定 `--params` 形状（例如 `INTERNAL_OS` 来源拼对了么），先这样试：

```bash
blueai-cli media-storage upload create --params '{
  "source_type": "INTERNAL_OS",
  "object_list": [{
    "os_type": "OSS",
    "bucket": "my-bucket",
    "region": "oss-cn-hangzhou",
    "object_keys": ["videos/a.mp4", "videos/b.mp4"]
  }],
  "target_storage": ["COS"]
}' --dry-run
```

输出会显示 CLI 即将发出的实际 body，确认无误再去掉 `--dry-run`。

---

## 9. 干净 cancel 长轮询

如果在 `upload result` 轮询时 Ctrl+C，CLI 会以 exit code 130 退出并在 stderr 输出 `task_id` + `last_status`，方便恢复。脚本可以这样保活：

```bash
trap 'echo "interrupted, last task_id was $TASK_ID"; exit 130' INT TERM
# ... while loop here
```

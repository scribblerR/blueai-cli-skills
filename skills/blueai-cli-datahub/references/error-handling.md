# DataHub 错误排查（CLI 版）

CLI 把所有错误统一包成 `BlueAIError`，输出形如：
```json
{"ok": false, "error": {"type": "...", "message": "...", "hint": "..."}}
```

`error.type` 决定退出码：

| type | 退出码 | 含义 |
|---|---|---|
| `success` | 0 | 成功 |
| `api_error` | 1 | DataHub 业务错误（看 message） |
| `validation` | 2 | 参数校验失败 |
| `auth` | 3 | apiKey 缺失或无效 |
| `network` | 4 | 网络/超时 |
| `internal` | 5 | CLI 内部错误 |
| (interrupted) | 130 | 用户 Ctrl-C（轮询中） |

---

## DataHub 业务错误码

CLI 把 DataHub 的 `code` 透传到 `error.message` 和 `error.detail` 里。常见的：

| Code | 含义 | 处理 |
|---|---|---|
| 0 | 成功 | — |
| 9001 | 请求参数错误 | 检查 `--params` 里的 JSON 字段 |
| 1003 | apiKey 无效 | `blueai-cli config init` 重新配 |
| 2000 | 资源不存在或无权限 | 确认 task_id / data_source_id 正确 |
| 9099 | 服务内部错误 | 重试，CLI 会对 5xx 自动 2 次重试 |

---

## 9001 — 请求参数错误

### 缺必填字段
```bash
# ❌ 缺 data_source
blueai-cli tools ai-batch openapi task-create --params '{
  "prompt": {"prompt_text": "分析：{{content}}"}
}'

# ✅
blueai-cli tools ai-batch openapi task-create --params '{
  "data_source": {"data_source_id": "ds-xxx"},
  "prompt": {"prompt_text": "分析：{{content}}"}
}'
```

### Prompt 缺占位符
```bash
# ❌ 没 {{}} 占位符（除非视觉任务）
'{"prompt": {"prompt_text": "请分析内容"}}'

# ✅
'{"prompt": {"prompt_text": "请分析：{{content}}"}}'
```

### 占位符语法错（带空格）
```bash
# ❌ {{ content }} 带空格 — 不识别
'{"prompt": {"prompt_text": "请分析：{{ content }}"}}'

# ✅ {{content}} 紧挨着
'{"prompt": {"prompt_text": "请分析：{{content}}"}}'
```

### 数据源冲突
```bash
# ❌ 三个字段同时给
'{"data_source": {"data_source_id": "ds-1", "data_source_url": "https://..."}}'

# ✅ 三选一
'{"data_source": {"data_source_id": "ds-1"}}'
```

### 视觉任务缺 vision_fields_names
```bash
# ❌ prompt_type 设了 VISION，但没指定哪一列是图片
'{"prompt": {"prompt_type": "PROMPT_TYPE_VISION", "prompt_text": "分析"}}'

# ✅
'{"prompt": {
  "prompt_type": "PROMPT_TYPE_VISION",
  "prompt_text": "分析",
  "prompt_run_config": {"vision_fields_names": ["img_url"]}
}}'
```

---

## 1003 / auth — apiKey 问题

退出码 3，`error.type=auth`：

```bash
# 检查当前配置
blueai-cli config show

# 重新配置
blueai-cli config init

# 或临时
export BLUEAI_API_KEY="..."
blueai-cli tools ai-batch openapi model-list --params '{}'

# 老配置升级
blueai-cli config migrate
```

> CLI 不会去用环境变量 `DATAHUB_API_KEY`。要么走 `BLUEAI_API_KEY`，要么走 credentials.json。

---

## 2000 — 资源不存在

最常见两种情况：

1. **task_id / data_source_id 拼错了**——直接复制粘贴上一步的输出，别手敲。
2. **apiKey 没有这条任务的权限**——确认 apiKey 是不是创建任务的那个；或者去后台把任务的 user_emails 加上。

```bash
# 用任务注册表反查 — CLI 提交过的任务都在 ~/.blueai/tasks.json
blueai-cli task list

# 查特定任务详情
blueai-cli task status <task_id>
```

---

## 9099 / network — 重试

CLI 已经内置：
- HTTP 5xx / 429：自动重试 2 次
- 429 优先看 `Retry-After`，否则指数退避（最长 10s，封顶 60s）

如果还是失败，多半是 DataHub 侧问题。等几分钟再试。

---

## 任务状态错误

任务进入 `TASK_STATUS_FAILED`、`TASK_STATUS_STOP`、`TASK_STATUS_CANCEL` 时 CLI 会把整个 body 透传出来。从中提取：

```bash
blueai-cli task wait --ids '[123]' --format json | jq '.data.data | {task_status, error_message}'
```

`task wait` 默认遇到失败会非 0 退出。

---

## 中断恢复

长轮询时 Ctrl-C / SIGTERM 会得到：
```json
{"ok": false, "error": {"type": "interrupted", "detail": {"task_id": 123, "last_status": "TASK_STATUS_RUNNING"}}}
```
退出码 130。任务在远端继续跑，下次回来用 `blueai-cli task status 123 --watch` 接着等就行。

---

## 上传文件错误

| 现象 | 原因 | 处理 |
|---|---|---|
| `error.type=validation`, message 提到 file_name | 没传 `--params '{"file_name":"..."}' ` 或扩展名错 | 必须带文件名（含扩展名），且是 `.csv/.xlsx/.xls/.json` |
| `error.type=network`, timeout | 文件太大或网络慢 | 单文件建议 < 100MB；CLI 用流式上传，重试时会重新打开文件 |
| 5xx | 网关问题 | 自动重试 2 次后失败，等等再试 |

> CLI 不跟随 multipart 上传的 301/302/307/308 重定向 — 流已经被消费完了。如果遇到 redirect 错误，多半是网关配置问题，找运维。

---

## 排查清单（出问题先过一遍）

1. **apiKey 配了吗？** `blueai-cli config show` 看不看得到 `apiKey` 字段
2. **能不能调通最简单的请求？** `blueai-cli tools ai-batch openapi model-list --params '{}'`
3. **--params 是合法 JSON 吗？** 复杂 JSON 用 `jq -n` 拼，别手撸字符串
4. **data_source 三选一了吗？** 别同时塞 `data_source_id` 和 `data_source_url`
5. **prompt 有占位符吗？** 至少一个 `{{列名}}`（视觉任务文本除外，但要 `vision_fields_names`）
6. **列名和 prompt 一致吗？** 区分大小写、不带空格
7. **视觉模型对吗？** `model-list --params '{"only_vision":true}'` 验证
8. **Gemini 用了 gcp_url 吗？** 不是 `url`，是 `gcp_url`，且数据源里要有这一列

---

## 拿不准用 dry-run

加 `--dry-run` 可以看 CLI 实际打算发什么请求（不会真发）：

```bash
blueai-cli tools ai-batch openapi task-create --dry-run --params '{
  "data_source": {"data_source_id": "ds-xxx"},
  "prompt": {"prompt_text": "分析：{{content}}"}
}'
```

调试 `--params` JSON 时尤其有用。

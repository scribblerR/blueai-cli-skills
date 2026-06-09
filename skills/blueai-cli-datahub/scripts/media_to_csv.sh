#!/usr/bin/env bash
# 把 Media Storage skill 的多文件上传输出转成 DataHub 可消费的 CSV。
#
# Media Storage 输出形如：
#   {"success":true,"data":{"files":[
#     {"file_name":"a.jpg","file_url":"https://...","gcp_url":"gs://...","media_id":"m1","success":true},
#     {"file_name":"b.jpg","file_url":"https://...","gcp_url":"gs://...","media_id":"m2","success":true}
#   ]}}
#
# 本脚本读 stdin（或文件参数）的 JSON，输出 CSV：
#   file_name,url,gcp_url,media_id
#
# 然后就可以：
#   ./media_to_csv.sh < media_output.json > media.csv
#   blueai-cli tools ai-batch openapi upload-file --params '{"file_name":"media.csv"}' --file media.csv

set -euo pipefail

INPUT="${1:-/dev/stdin}"

# 兼容两种格式：
#   1. 多文件：{"data":{"files":[...]}}
#   2. 单文件：{"data":{"file_url":"...","gcp_url":"...","media_id":"..."}}
# 单文件时把它包成单元素数组统一处理。

jq -r '
  # 取 files 数组；如果是单文件结构，包成数组
  (.data.files // [.data])
  | map(select(.success != false))    # 跳过失败的项
  | (
      ["file_name","url","gcp_url","media_id"],            # 表头
      (.[] | [
        (.file_name // "unknown"),
        (.file_url // .url // ""),
        (.gcp_url // ""),
        (.media_id // "")
      ])
    )
  | @csv
' "$INPUT"

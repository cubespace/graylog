#!/bin/bash

# Replace these variables with your actual server and auth details
SERVER="https://graylog.test.local"
USER="admin:quangkk99"
CERT_PATH="/etc/nginx/ssl-certificate/localhost.crt"
INFO_INDEX="/root/index-sets-vcenter.json"

# Đọc file JSON và gửi từng index set
jq -c '.index_sets[]' "$INFO_INDEX" | while IFS= read -r index; do
  curl --cacert "$CERT_PATH" -X POST "$SERVER/api/system/indices/index_sets" \
    -H "Accept: application/json" \
    -H "X-Requested-By: XMLHttpRequest" \
    -u "$USER" \
    -H "Content-Type: application/json" \
    -d "$index"
done
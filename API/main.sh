#!/bin/bash

# Replace these variables with your actual server and auth details
SERVER="https://graylog.thanhquang.local"
USER="admin:minhlaquang"
CERT_PATH="/etc/nginx/ssl-certificate/localhost.crt"
INFO_INDEX="/root/index-sets-vcenter.json"
INFO_STREAM="/root/stream-vcenter.json"

# Post index sets
jq -c '.index_sets[]' "$INFO_INDEX" | while IFS= read -r index; do
  curl --cacert "$CERT_PATH" -X POST "$SERVER/api/system/indices/index_sets" \
    -H "Accept: application/json" \
    -H "X-Requested-By: XMLHttpRequest" \
    -u "$USER" \
    -H "Content-Type: application/json" \
    -d "$index"
done

API_URL="https://graylog.thanhquang.local/api/system/indices/index_sets"
response=$(curl -s -X GET "$API_URL" \
  --cacert "$CERT_PATH" \
  -u "$USER" \
  -H "Content-Type: application/json")

# In nội dung response để kiểm tra
#echo "Response: $response"
# Trích xuất ID của các index set cần thiết
id_vcenter_auth=$(echo "$response" | jq -r '.index_sets[] | select(.index_prefix == "vcenter_auth") | .id')
id_vcenter_vm_reconfig=$(echo "$response" | jq -r '.index_sets[] | select(.index_prefix == "vcenter_vm_reconfig") | .id')
id_vcenter_global_perm=$(echo "$response" | jq -r '.index_sets[] | select(.index_prefix == "vcenter_global_perm") | .id')

# replace index_set_id 
sed -i 's/"index_set_id": ""/"index_set_id": "'"$id_vcenter_auth"'"/' "$INFO_STREAM"
sed -i 's/"index_set_id": ""/"index_set_id": "'"$id_vcenter_global_perm"'"/' "$INFO_STREAM"
sed -i 's/"index_set_id": ""/"index_set_id": "'"$id_vcenter_vm_reconfig"'"/' "$INFO_STREAM"


# Post stream
jq -c '.streams[]' "$INFO_STREAM" | while IFS= read -r stream; do
  curl --cacert "$CERT_PATH" -X POST "$SERVER/api/streams" \
    -H "Accept: application/json" \
    -H "X-Requested-By: XMLHttpRequest" \
    -u "$USER" \
    -H "Content-Type: application/json" \
    -d "$stream"
done

#!/bin/bash

# Cloudflare R2 S3 endpoint
ENDPOINT="https://4ecc77f16aaa2e53317a19267e3034a4.r2.cloudflarestorage.com"
PROFILE="default"
DELETE_MODE=false
LOAD_MODE=false

# Handle optional --delete flag
if [[ "$1" == "--delete" ]]; then
  DELETE_MODE=true
  echo "⚠️  DELETE MODE ENABLED: mismatched local files will be removed."
else
  echo "🔎 Preview mode: mismatched local files will be listed but not deleted."
fi
if [[ "$1" == "--load" ]]; then
  LOAD_MODE=true
  echo "⚠️  LOADING MODE ENABLED: get from the s3 to the folder"
else
  echo "🔎 Preview mode: NOT LOAD."
fi

# Function to compare S3 and local directory by file name and size
compare_and_handle_mismatches_fast() {
  local s3_path=$1
  local local_path=$2
  local s3_list="/tmp/s3_files_$(basename $local_path).txt"
  local local_list="/tmp/local_files_$(basename $local_path).txt"
  local mismatches="/tmp/mismatches_$(basename $local_path).txt"

  echo ""
  echo "🔍 Scanning:"
  echo "   S3 Path:    $s3_path"
  echo "   Local Path: $local_path"

  echo "📥 Generating file list from S3..."
  aws s3 ls "$s3_path" --recursive --endpoint-url "$ENDPOINT" --profile "$PROFILE" \
    | awk '{size=$3; $1=""; $2=""; $3=""; path=substr($0,4); sub(/^snapshots\/[^/]+\//,"",path); print path, size}' \
    | sort > "$s3_list"

  echo "📂 Generating file list from local disk..."
  find "$local_path" -type f -printf "%P %s\n" | sort > "$local_list"

  echo $s3_list
  echo $local_list

  echo "⚖️ Comparing files..."

  join -j 1 <(sort "$s3_list") <(sort "$local_list") -o 1.1,1.2,2.2 \
    | awk '$2 != $3 {print $1}' > "$mismatches"

  mismatch_count=$(wc -l < "$mismatches")

  if [[ "$mismatch_count" -eq 0 ]]; then
    echo "✅ All files match in name and size for $local_path"
    return
  fi

  echo "❌ Found $mismatch_count mismatched files in $local_path"

  if $DELETE_MODE; then
    echo "🗑 Deleting mismatched local files..."
    cat "$mismatches" | sed "s#^#$local_path/#" | xargs -P4 -I{} rm -f "{}"
    echo "✅ Deleted $mismatch_count mismatched local files."
  else
    echo "📋 Mismatched files (up to 50 shown):"
    head -n 50 "$mismatches"
    echo "ℹ️ Full list saved to: $mismatches"
    echo "➡️ To delete mismatches, rerun the script with: $0 --delete"
  fi
  if $LOAD_MODE; then
    while read f; do
      aws s3 cp \
        --endpoint-url $ENDPOINT \
        $s3_path$f \
        $local_path
    done < $mismatches
  fi
}

# Call for both store and archive
compare_and_handle_mismatches_fast \
  "cloudflare-r2:mainnet/snapshots/store" \
  "./supra_rpc_configs/rpc_store/"

compare_and_handle_mismatches_fast \
  "cloudflare-r2:mainnet/snapshots/archive" \
  "./supra_rpc_configs/rpc_archive/"


if $LOAD_MODE; then
  while read f; do
    aws s3 cp \
      --endpoint-url $ENDPOINT \
       $s3_path$f/$f \
       $local_path
  done < $mismatches

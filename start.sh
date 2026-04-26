#!/usr/bin/env bash
set -euo pipefail
export ADDR=":8082"
export LOG_BODY_MAX_CHARS=0
export LOG_STREAM_TEXT_PREVIEW_CHARS=0
if [ ! -f ./claude-nvidia-proxy ]; then
  go build -o claude-nvidia-proxy .
fi
exec ./claude-nvidia-proxy

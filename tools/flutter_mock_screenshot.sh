#!/usr/bin/env bash
set -euo pipefail

out="${1:-build/llb_mock_screenshot.png}"
mkdir -p "$(dirname "$out")"

device_args=()
if [[ -n "${FLUTTER_DEVICE_ID:-}" ]]; then
  device_args=(-d "$FLUTTER_DEVICE_ID")
fi

flutter run \
  --dart-define=LLB_USE_MOCK_DATA=true \
  --no-resident \
  "${device_args[@]}"

flutter screenshot -o "$out"
echo "$out"

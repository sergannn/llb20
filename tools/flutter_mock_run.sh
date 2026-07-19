#!/usr/bin/env bash
set -euo pipefail

flutter run \
  --dart-define=LLB_USE_MOCK_DATA=true \
  "$@"

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
swift run --disable-sandbox --cache-path "$PWD/.build/cache" ClickThroughCoreTests
swift run --disable-sandbox --cache-path "$PWD/.build/cache" ClickThroughEngineTests

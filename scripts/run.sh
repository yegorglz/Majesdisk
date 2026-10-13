#!/bin/bash
# Launch through `open` so macOS privacy checks attribute file access to MajesDisk, not Terminal.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh debug
open dist/MajesDisk.app --args "$@"

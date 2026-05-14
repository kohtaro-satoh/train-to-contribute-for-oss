#!/usr/bin/env bash
# コンテナを停止する（Jenkins home ボリュームは保持）
# ボリュームも削除したい場合は --clean フラグを使う
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CLEAN=false
for arg in "$@"; do
  [[ "$arg" == "--clean" ]] && CLEAN=true
done

if $CLEAN; then
  echo "[INFO] Stopping containers and removing Jenkins home directories ..."
  docker compose down --remove-orphans
  for jh in jh8081 jh8082 jh8083; do
    if [[ -d "$SCRIPT_DIR/$jh" ]]; then
      rm -rf "$SCRIPT_DIR/$jh"
      echo "[INFO] Removed $SCRIPT_DIR/$jh"
    fi
  done
  echo "[INFO] Jenkins home directories removed."
else
  echo "[INFO] Stopping containers (Jenkins home volumes preserved) ..."
  docker compose down --remove-orphans
  echo "[INFO] Containers stopped."
  echo "[INFO] To also delete volumes: ./stop.sh --clean"
fi

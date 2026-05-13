#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "[INFO] Repo: $REPO_DIR"
echo "[INFO] Stopping local Jenkins controllers if running ..."

for port in 8081 8082 8083; do
  home="$REPO_DIR/work/jenkins-home-${port}"
  pkill -f "-DjenkinsHome=${home}" 2>/dev/null || true
done

# Safety net for Jenkins war processes launched from this repository.
pkill -f "${REPO_DIR}/work/jenkins-home-.*jenkins-war.*--prefix=/jenkins" 2>/dev/null || true

sleep 1

echo "[INFO] Remaining listeners on 8081/8082/8083 (if any):"
ss -ltnp | grep -E ':(8081|8082|8083)' || echo "[OK] No listeners on 8081/8082/8083"

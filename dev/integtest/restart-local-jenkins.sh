#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$REPO_DIR/work/logs"

mkdir -p "$LOG_DIR"

if [[ -x "$HOME/.local/apache-maven-3.9.9/bin/mvn" ]]; then
  MVN="$HOME/.local/apache-maven-3.9.9/bin/mvn"
else
  MVN="mvn"
fi

start_one() {
  local port="$1"
  local home="$REPO_DIR/work/jenkins-home-${port}"
  local log="$LOG_DIR/jenkins-${port}.log"

  mkdir -p "$home"

  echo "[INFO] Starting Jenkins ${port} ..."
  nohup "$MVN" \
    -f "$REPO_DIR/pom.xml" \
    -DskipTests \
    -Dhost=0.0.0.0 \
    -Dport="$port" \
    -DjenkinsHome="$home" \
    hpi:run >"$log" 2>&1 &

  local retries=120
  for ((i=1; i<=retries; i++)); do
    if curl -fsS "http://127.0.0.1:${port}/jenkins/login" >/dev/null 2>&1; then
      echo "[OK] Jenkins ${port} is up"
      return 0
    fi
    sleep 1
  done

  echo "[WARN] Jenkins ${port} did not become ready in time. Check $log"
}

stop_existing() {
  echo "[INFO] Stopping existing local Jenkins instances (if any) ..."

  for port in 8081 8082 8083; do
    local home="$REPO_DIR/work/jenkins-home-${port}"
    pkill -f "-DjenkinsHome=${home}" 2>/dev/null || true
  done

  # Safety net: if any matching Jenkins war process remains for this repo, stop it.
  pkill -f "${REPO_DIR}/work/jenkins-home-.*jenkins-war.*--prefix=/jenkins" 2>/dev/null || true

  sleep 1
}

main() {
  echo "[INFO] Repo: $REPO_DIR"
  echo "[INFO] Maven: $MVN"

  stop_existing

  start_one 8081
  start_one 8082
  start_one 8083

  echo "[INFO] All start requests sent."
  echo "[INFO] URLs:"
  echo "  - http://localhost:8081/jenkins/"
  echo "  - http://localhost:8082/jenkins/"
  echo "  - http://localhost:8083/jenkins/"
  echo "[INFO] Logs: $LOG_DIR"
}

main "$@"

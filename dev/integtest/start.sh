#!/usr/bin/env bash
# ローカル開発用: lockable-resources-plugin を 3 コンテナで起動する
# 使い方: ./start.sh [--clean]
#   --clean : Jenkins home ボリュームを削除してから起動（初期化）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PLUGIN_DIR 環境変数が指定されている場合はそちらを優先する。
# 相対パスで渡された場合は start.sh からの相対として解決する。
# 未指定時は start.sh と同じディレクトリに lockable-resources-plugin が
# clone されていると仮定する。
if [[ -n "${PLUGIN_DIR:-}" ]]; then
  # 相対パスを絶対パスに正規化（start.sh の位置を基準）
  PLUGIN_DIR="$(cd "$SCRIPT_DIR" && cd "$PLUGIN_DIR" && pwd)"
else
  PLUGIN_DIR="$SCRIPT_DIR/lockable-resources-plugin"
fi

CLEAN=false
for arg in "$@"; do
  [[ "$arg" == "--clean" ]] && CLEAN=true
done

# ---------------------------------------------------------------------------
# 1. Maven を特定
# ---------------------------------------------------------------------------
if [[ -x "$HOME/.local/apache-maven-3.9.9/bin/mvn" ]]; then
  MVN="$HOME/.local/apache-maven-3.9.9/bin/mvn"
else
  MVN="mvn"
fi

echo "[INFO] Plugin dir: $PLUGIN_DIR"
echo "[INFO] Maven     : $MVN"

# ---------------------------------------------------------------------------
# 2. プラグインをビルド
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Building lockable-resources plugin (mvn package -DskipTests) ..."
(cd "$PLUGIN_DIR" && "$MVN" package -DskipTests -q)

# ---------------------------------------------------------------------------
# 3. ビルド成果物を Docker ビルドコンテキストへコピー
# ---------------------------------------------------------------------------
HPI_SRC="$(ls "$PLUGIN_DIR/target/lockable-resources"*.hpi 2>/dev/null | head -1 || true)"
if [[ -z "$HPI_SRC" ]]; then
  echo "[ERROR] HPI not found in $PLUGIN_DIR/target/. Build may have failed."
  exit 1
fi
cp "$HPI_SRC" "$SCRIPT_DIR/docker/lockable-resources.hpi"
echo "[INFO] Copied: $HPI_SRC -> docker/lockable-resources.hpi"

# ---------------------------------------------------------------------------
# 4. ボリューム削除（--clean 指定時のみ）
# ---------------------------------------------------------------------------
cd "$SCRIPT_DIR"
if $CLEAN; then
  echo ""
  echo "[INFO] --clean: stopping containers and removing Jenkins home directories ..."
  docker compose down --remove-orphans 2>/dev/null || true
  for jh in jh8081 jh8082 jh8083; do
    if [[ -d "$SCRIPT_DIR/$jh" ]]; then
      rm -rf "$SCRIPT_DIR/$jh"
      echo "[INFO] Removed $SCRIPT_DIR/$jh"
    fi
  done
fi

# ---------------------------------------------------------------------------
# 5. Jenkins home ディレクトリを用意
# ---------------------------------------------------------------------------
for jh in jh8081 jh8082 jh8083; do
  if [[ ! -d "$SCRIPT_DIR/$jh" ]]; then
    mkdir -p "$SCRIPT_DIR/$jh"
    echo "[INFO] Created $SCRIPT_DIR/$jh"
  fi
done

# ---------------------------------------------------------------------------
# 6. Docker イメージをビルド
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Building Docker images ..."
docker compose build

# ---------------------------------------------------------------------------
# 6. コンテナを起動
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Starting containers ..."
docker compose up -d


# ---------------------------------------------------------------------------
# 8. 起動確認（ポートごとにポーリング）
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Waiting for Jenkins instances to become ready ..."
for port in 8081 8082 8083; do
  ready=false
  for i in $(seq 1 120); do
    if curl -fsS "http://127.0.0.1:${port}/jenkins/login" >/dev/null 2>&1; then
      echo "[OK]   Jenkins ${port} is up (${i}s)"
      ready=true
      break
    fi
    sleep 2
  done
  if ! $ready; then
    echo "[WARN] Jenkins ${port} did not become ready within 240s"
    echo "       Check logs: docker compose logs jenkins-${port}"
  fi
done

echo ""
echo "----------------------------------------------------------------------"
echo " Jenkins 3-controller dev environment"
echo "----------------------------------------------------------------------"
echo "  http://localhost:8081/jenkins/  (admin / admin)"
echo "  http://localhost:8082/jenkins/  (admin / admin)"
echo "  http://localhost:8083/jenkins/  (admin / admin)"
echo ""
echo " Logs  : docker compose logs -f"
echo " Stop  : ./stop.sh"
echo " Clean : ./start.sh --clean   (removes jh8081-8083 directories)"
echo "----------------------------------------------------------------------"

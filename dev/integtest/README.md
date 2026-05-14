# lockable-resources-plugin Docker 開発環境

Jenkins 3 コントローラー（ポート 8081/8082/8083）を Docker Compose で起動し、
remote lock 機能の統合テストを行うための開発環境です。

## 前提条件

- Docker（`docker compose` コマンドが使えること）
- JDK 17 以上
- Maven（`$HOME/.local/apache-maven-3.9.9/bin/mvn` があればそちらを優先、なければ `mvn`）

## ディレクトリ構成

```
integtest/
├── README.md               このファイル
├── docker-compose.yml      3 コントローラー定義
├── start.sh                ビルド＆起動スクリプト
├── stop.sh                 停止スクリプト
├── .gitignore
├── docker/
│   ├── Dockerfile
│   ├── plugins.txt         依存プラグイン一覧
│   └── init.groovy.d/
│       └── 00-init.groovy  admin ユーザー自動作成（dev only）
├── lockable-resources-plugin/   ← プラグインのソース（後述）
├── jh8081/                 Jenkins home（自動生成、.gitignore 対象）
├── jh8082/
└── jh8083/
```

## セットアップ

### 1. プラグインのソースを用意する

`lockable-resources-plugin` のソースを `integtest/` と同じ場所に用意します。
方法は以下のいずれかです。

**A. 直接 clone する（推奨）**

```bash
cd path/to/integtest
git clone https://github.com/jenkinsci/lockable-resources-plugin.git
```

**B. シンボリックリンクを張る**

すでに別の場所に clone 済みの場合：

```bash
cd path/to/integtest
ln -s /path/to/your/lockable-resources-plugin lockable-resources-plugin
```

**C. 環境変数で場所を指定する**

```bash
# 絶対パス
PLUGIN_DIR=/path/to/lockable-resources-plugin ./start.sh

# start.sh からの相対パス
PLUGIN_DIR=../../../lockable-resources-plugin ./start.sh
```

### 2. 起動する

```bash
./start.sh
```

`start.sh` の処理内容：

1. `mvn package -DskipTests` でプラグインをビルド
2. ビルドした `.hpi` を `docker/` へコピー
3. `jh8081`〜`jh8083` ディレクトリを作成（初回のみ）
4. Docker イメージをビルド
5. 3 コンテナを起動
6. 各コントローラーの起動を確認

起動後のアクセス先：

| URL | 認証情報 |
|---|---|
| http://localhost:8081/jenkins/ | admin / admin |
| http://localhost:8082/jenkins/ | admin / admin |
| http://localhost:8083/jenkins/ | admin / admin |

> どのディレクトリからでも実行できます:
> ```bash
> ~/projects/jenkins/remote-lr/lrr-notes/dev/integtest/start.sh
> ```

## 操作

### 停止（Jenkins home は保持）

```bash
./stop.sh
```

コンテナを停止しますが、`jh8081`〜`jh8083` のデータは残ります。
次回 `./start.sh` で続きから使えます。

### 完全初期化（Jenkins home も削除）

```bash
./start.sh --clean
```

または：

```bash
./stop.sh --clean
./start.sh
```

`jh8081`〜`jh8083` ディレクトリを削除してから起動します。
管理者設定・パイプライン設定などをすべてリセットしたいときに使います。

### ログを確認する

```bash
# 全コントローラーのログをフォロー
docker compose -f path/to/integtest/docker-compose.yml logs -f

# 特定コントローラーのみ
docker compose -f path/to/integtest/docker-compose.yml logs -f jenkins-8081
```

`integtest/` ディレクトリにいる場合は `-f` オプション不要：

```bash
cd path/to/integtest
docker compose logs -f jenkins-8082
```

## プラグインを更新して再起動する

ソースを修正したら `start.sh` を再実行するだけです。
ビルド→イメージ再構築→コンテナ再起動まで一括で行います。

```bash
./start.sh
```

Jenkins home のデータは保持されます。初期化したい場合は `--clean` を付けます。

## よくある問題

### `PLUGIN_DIR` が見つからない

```
[ERROR] HPI not found in .../target/
```

`PLUGIN_DIR` が正しく解決されていないか、ビルドに失敗しています。

- `echo $PLUGIN_DIR` で解決先を確認する
- `lockable-resources-plugin/` の clone またはシンボリックリンクを確認する
- Maven のエラーログを確認する

### ポートが使用中

```
Bind for 0.0.0.0:8081 failed: port is already allocated
```

既存コンテナまたは別プロセスが占有しています。

```bash
./stop.sh
./start.sh
```

### コンテナが READY にならない

240 秒以内に `/jenkins/login` が返らない場合：

```bash
docker compose logs jenkins-8081
```

でログを確認してください。

# ローカル開発セットアップ手順（WSL Ubuntu 24 / lockable-resources-plugin）

このメモは個人利用向けです。
目的は、`hpi:run` で Jenkins を起動し、最終的に 3 台（8081/8082/8083）を同時に扱えるようにすることです。

## 1. 前提

- OS: WSL2 Ubuntu 24
- リポジトリ: `lockable-resources-plugin`
- 以降のコマンドはリポジトリ直下で実行

```sh
cd /home/ksato/projects/jenkins/lockable-resources-plugin
```

## 2. 必要パッケージの導入

### Maven

最初は `mvn` が無い状態だったため、APT で導入。

```sh
sudo apt update
sudo apt install -y maven
```

### JDK（重要）

`release version 17 not supported` エラー回避のため、JDK を導入。

```sh
sudo apt install -y openjdk-21-jdk
```

確認:

```sh
java -version
javac -version
```

## 3. Maven 3.9.9 の利用

環境依存で `Unknown packaging: hpi` が出るケースがあるため、
この環境では Maven 3.9.9 を使用。

利用コマンド例:

```sh
$HOME/.local/apache-maven-3.9.9/bin/mvn -v
```

以降、起動系はこの Maven を優先して使う。

## 4. `hpi:run` の実行オプション（今回のポイント）

### ポート指定

`-Djetty.port=xxxx` ではなく `-Dport=xxxx` を使う。

### バインドアドレス指定

Windows ホストブラウザからアクセスしやすくするため、`-Dhost=0.0.0.0` を使う。

### Jenkins Home の明示

複数台運用のため、`-DjenkinsHome=...` を必ず分ける。

## 5. 1 台起動の例

```sh
$HOME/.local/apache-maven-3.9.9/bin/mvn \
  -DskipTests \
  -Dhost=0.0.0.0 \
  -Dport=8081 \
  -DjenkinsHome=$PWD/work/jenkins-home-8081 \
  hpi:run
```

アクセス先:

- `http://localhost:8081/jenkins/`

※ このプラグインの開発起動は `/jenkins/` プレフィックス付き。

## 6. 3 台構成

使用ポート:

- 8081
- 8082
- 8083

Jenkins home:

- `work/jenkins-home-8081`
- `work/jenkins-home-8082`
- `work/jenkins-home-8083`

`work/` は `.gitignore` 対象なのでローカル専用データ置き場として使える。

## 7. 追加したローカル用スクリプト

### 再起動（停止してから 3 台起動）

ファイル:

- `work/restart-local-jenkins.sh`

実行:

```sh
cd /home/ksato/projects/jenkins/lockable-resources-plugin/work
./restart-local-jenkins.sh
```

動作:

1. 既存 8081/8082/8083 を停止（起動中のみ）
2. 3 台を順番に起動
3. `/jenkins/login` で起動確認
4. ログ出力

ログ:

- `work/logs/jenkins-8081.log`
- `work/logs/jenkins-8082.log`
- `work/logs/jenkins-8083.log`

### 停止のみ

ファイル:

- `work/stop-local-jenkins.sh`

実行:

```sh
cd /home/ksato/projects/jenkins/lockable-resources-plugin/work
./stop-local-jenkins.sh
```

動作:

- 8081/8082/8083 を停止
- 最後にポート待受の残りを表示

## 8. よくある症状と対処

### `mvn: command not found`

- Maven 未インストール。`sudo apt install -y maven`

### `Unknown packaging: hpi`

- Maven 実装差異が原因の可能性。
- この環境では Maven 3.9.9 を使うと解消。

### `release version 17 not supported`

- JRE のみで `javac` が無い状態。
- `openjdk-21-jdk` を導入。

### `Address already in use`

- 同一ポートに既存プロセスあり。
- 停止してから再実行（`work/stop-local-jenkins.sh`）。

### `hpi:run` が `BUILD FAILURE` で終了する（code 143）

- `Ctrl+C` で停止したときの終了コードとして発生する。
- 停止操作としては正常。

## 9. 現在の個人運用ルール

- ローカル専用ファイルは `work/` 配下に置く。
- 個人メモは `work/` 以下で管理（コミット対象外）。
- 3 台起動はスクリプト経由を基本にする。

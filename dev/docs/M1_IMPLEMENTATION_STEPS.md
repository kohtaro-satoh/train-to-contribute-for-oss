# M1 Implementation Steps (Remote lock - Phase 1 / M1)

このファイルは個人用の進捗トラッカーです。
実装を機能単位のコミットに分け、後から追跡できるようにします。

## 使い方

- 各ステップは完了したらチェックを入れる。
- 各ステップで「コミット」「対象ファイル」「確認結果」を記録する。
- 1ステップ 1コミットを基本にする（必要なら 1ステップ複数コミットでも可）。

## M1 のゴール

- `lock(..., serverId: 'X')` の明示指定で remote lock を扱える最小実装を作る。
- まずは peer mode の最小成立を優先し、後続で拡張しやすい構造にする。

## ステップ一覧

### 0. 事前準備（ブランチ/環境）

- [x] 作業ブランチを最新 master から作成済み
- [x] 3 controller ローカル環境（8081/8082/8083）で起動確認済み
- [x] 既存テストが通る基準点を確認済み

記録:
- 日付: 2026-05-09
- コミット: 739d6da
- メモ: $HOME/.local/apache-maven-3.9.9/bin/mvn test を実行し BUILD SUCCESS（Tests run: 238, Failures: 0, Errors: 0, Skipped: 1, Total time: 13:42）を確認。

---

### 1. リモート接続設定モデルの追加

目的:
- `serverId -> (url, credentialsId)` の設定を持てる土台を追加する。

実装候補:
- `LockableResourcesManager` に `remotes` 設定を追加
- 必要なら専用 model クラス（例: `RemoteConnection`）を追加
- 保存/読み込み/バリデーションの最小実装

完了条件:
- 設定が保存され、再起動後も読み出せる
- 不正値に対する最低限の入力チェックがある

- [x] 実装完了
- [x] 単体確認完了

記録:
- 日付: 2026-05-09
- コミット: 5456a78
- 変更ファイル:
  - src/main/java/.../RemoteConnection.java (新規)
  - src/main/java/.../LockableResourcesManager.java (編集)
  - src/test/java/.../RemoteConnectionTest.java (新規)
  - src/test/java/.../LockableResourcesManagerRemoteConnectionTest.java (新規)
- 確認結果: $HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=RemoteConnectionTest,LockableResourcesManagerRemoteConnectionTest を実行し成功（Tests run: 15, Failures: 0, Errors: 0, Skipped: 0）。
- 補足: LockableResourcesManager は remotes を List で保持し、getRemotesAsMap() で動的に Map 変換。readResolve() で旧設定ロード時の null を空リストに正規化。reload を使った永続化テストを追加。

---

### 2. リモート API クライアントの骨格追加

目的:
- remote 側 REST へアクセスする最小クライアント層を分離して作る。

実装方針:
- クライアント責務は「HTTP呼び出し層 + DTO + エラー変換」に限定し、LockStepExecution への接続は次ステップへ分離
- 認証は Authorization ヘッダを受け取る形にして、資格情報解決責務は呼び出し側へ分離
- 既定値（内部定数）:
  - pollIntervalSeconds = 3
  - heartbeatIntervalSeconds = 10
  - requestTimeoutSeconds = 10
- エラー方針: fail-closed（4xx/5xx/通信失敗を RemoteApiException へ変換）
- URL方針: `/lockable-resources/remote/v1` を固定し、base URL の末尾スラッシュ差異を吸収
- ログ方針: serverId/method/path/status のみ出力し、認証情報は出力しない

完了条件:
- ダミー呼び出しを通せる（またはモックで検証できる）
- 失敗時の戻り値/例外方針が明確

- [x] 実装完了
- [x] 単体確認完了

記録:
- 日付: 2026-05-10
- コミット: d40c5dc
- 変更ファイル:
  - src/main/java/.../remote/RemoteClientDefaults.java (新規)
  - src/main/java/.../remote/RemoteAcquireState.java (新規)
  - src/main/java/.../remote/RemoteAcquireStatus.java (新規)
  - src/main/java/.../remote/RemoteApiException.java (新規)
  - src/main/java/.../remote/RemoteApiClient.java (新規)
  - src/test/java/.../remote/RemoteAcquireStatusTest.java (新規)
  - src/test/java/.../remote/RemoteApiClientTest.java (新規)
- 確認結果: $HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=RemoteApiClientTest,RemoteAcquireStatusTest を Step2 コミット上で実行し成功（Tests run: 6, Failures: 0, Errors: 0, Skipped: 0）。
- 補足: レビュー指摘に合わせて、lockId欠如時のhttpStatus伝播、JSON parse失敗ログ、baseUrl防御チェック、null state→UNKNOWNフォールバックを反映済み。cancel 概念を Phase1 から外す方針に合わせ、Step2 履歴上も cancel API 実装を含めない形へ整理済み。

---

### 3. acquire/release の remote 呼び出しフロー実装

目的:
- acquire -> poll -> acquired/rejected -> release の最小ライフサイクルを実装する。

実装方針:
1. client 側はローカル queue に積まない（remote acquire は非同期ポーリングで追跡）
2. `start()` は remote acquire 登録後に即 return（non-blocking）
3. `GET /acquire/{lockId}` を 3 秒間隔でポーリング
4. 状態遷移:
  - `QUEUED` は継続
  - `ACQUIRED` で body 実行開始
  - `SKIPPED` は成功終了（body 未実行）
  - `FAILED` / `EXPIRED` は失敗終了
  - `CANCELLED` は中断扱い
5. heartbeat は body 実行中のみ送信し、body 完了で release
6. 中断時も release を試行（cancel 概念は Phase1 から除外）
7. fail-closed（通信失敗時に自動解放しない）
8. ログは `serverId / lockId / state` を中心に出し、認証情報は出力しない
9. RemoteApiClient の API 範囲は acquire/status + heartbeat/release（内部識別子は lockId 統一）
10. 再起動耐性は将来拡張しやすいフィールド設計に留め、完全復旧は次段で対応

完了条件:
- remote lock の取得/解放が end-to-end で成立
- 失敗時のログと終了動作が定義済み

- [x] 実装完了
- [x] 単体確認完了

記録:
- 日付: 2026-05-10
- コミット: fb25b42
- 変更ファイル:
  - src/main/java/.../remote/RemoteApiClient.java (編集: heartbeat/release + optional Authorization header)
  - src/main/java/.../LockStepExecution.java (編集: remote enqueue/poll/heartbeat/release フロー)
  - src/main/java/.../LockStep.java (編集: serverId DataBoundSetter 追加)
- 確認結果: $HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=LockStepTest,RemoteApiClientTest,RemoteAcquireStatusTest を実行し成功（Tests run: 37, Failures: 0, Errors: 0, Skipped: 0）。
- 補足: cancel 概念を Phase1 から除外する方針に合わせ、abort/完了とも release ベースでクリーンアップする実装へ整理済み。credentialsId は Phase1 では Authorization ヘッダーへ直接変換せず、認証未実装の扱いを明示している。

---

### 4. LockStep へ `serverId` 追加

目的:
- DSL から `serverId` を受け取り、local/remote の分岐に利用可能にする。

実装候補:
- `LockStep` に `serverId` フィールド追加
- Descriptor のバリデーション/補完（必要なら）
- `LockStepExecution` で remote 経路へ分岐

完了条件:
- `lock(resource: 'X', serverId: 'A')` が解釈される
- `serverId` なしの既存挙動が壊れない

- [x] 実装完了
- [x] 単体確認完了

記録:
- 日付: 2026-05-10
- コミット: fb25b42
- 変更ファイル:
  - src/main/java/.../LockStep.java (編集: serverId DataBoundSetter 追加)
  - src/main/java/.../LockStepExecution.java (編集: serverId 分岐による remote フロー接続)
- 確認結果: $HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=LockStepTest を実行し成功（Tests run: 31, Failures: 0, Errors: 0, Skipped: 0）。
- 補足: 実装は Step3 コミット内で同時に取り込んだため、履歴上は同一コミットで管理。

---

### 5. remote 側 REST エンドポイント（M1 必須範囲）

目的:
- M1 必要範囲のエンドポイントを実装する。

想定対象:
- `POST /acquire`
- `GET /acquire/{lockId}`
- `POST /lease/{lockId}/release`（最低限）

完了条件:
- local 側から呼べる
- 基本的なリクエスト/レスポンス仕様が固まる

- [ ] 実装完了
- [ ] 単体確認完了

記録:
- 日付:
- コミット:
- 変更ファイル:
- 確認結果:
- 補足:

---

### 6. 最小 UI/可視化（M1 で必要な範囲のみ）

目的:
- 実行時に追える最低限の表示を入れる。

実装候補:
- build log へ remote 対象の `serverId` や状態遷移を出力
- 必要なら LR 画面に最小情報表示

完了条件:
- 失敗時に原因追跡しやすい情報が残る

- [ ] 実装完了
- [ ] 動作確認完了

記録:
- 日付:
- コミット:
- 変更ファイル:
- 確認結果:
- 補足:

---

### 7. テスト（M1 の成立確認）

目的:
- 回帰防止のため、M1 の核心を自動テストで固定する。

優先テスト:
- `serverId` ありの分岐
- `serverId` なし既存挙動の維持
- remote acquire 成功/失敗の代表ケース

完了条件:
- 追加テストが安定して通る
- 主要ケースが再現可能

- [ ] 実装完了
- [ ] CI 相当のローカル実行で確認完了

記録:
- 日付:
- コミット:
- 変更ファイル:
- 確認結果:
- 補足:

---

## E2E 確認チェック（3 controller）

- [ ] 8081 -> 8082 の remote lock が取得できる
- [ ] 8083 から同一 resource を叩くと待機/拒否の期待挙動になる
- [ ] release 後に待機側が進む
- [ ] 異常系（remote down, timeout, auth error）で fail-closed になる

記録:
- 日付:
- 実施者:
- 結果:
- 問題点:

## コミット運用ルール（この作業向け）

- 1ステップ 1コミットを基本とする
- コミットメッセージは命令形で簡潔に書く
- ステップ跨ぎの変更は避ける
- 仕様変更が入ったらこのファイルのステップ定義も更新する

## 現在ステータス

- 開始日: 2026-05-09
- 現在ステップ: 3（Step2 amend 完了、Step3 は stash 退避中）
- 次アクション: `stash@{0}` を適用して Step3 実装を lockId 統一版として再調整し、Step3コミットを作成
- ブロッカー: なし

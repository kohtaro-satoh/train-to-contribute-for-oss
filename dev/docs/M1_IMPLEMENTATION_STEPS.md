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
- コミット: 739d6da（※ rebase 後は e4f70c3 が基点。M1 完了後に最終確認し更新予定）
- メモ: $HOME/.local/apache-maven-3.9.9/bin/mvn test を実行し BUILD SUCCESS（Tests run: 238, Failures: 0, Errors: 0, Skipped: 1, Total time: 13:42）を確認。
  2026-05-14 時点で PR #1028 cherry-pick（NodesMirror パッケージ修正）を master に適用後、feature ブランチを rebase し cold build でも BUILD SUCCESS（Tests run: 238, Failures: 0, Errors: 0, Skipped: 1）を確認。
  - PR #1028 は upstream 未マージのため、ローカル master に cherry-pick（コミット `e4f70c3`）して対処中。
  - Skipped: 1 は `LockStepInversePrecedenceTest#lockInverseOrderWithLabel`。JENKINS-40787 / GitHub #861 の既存バグ（ラベルベースロックで inversePrecedence が適用されずハングする）により `@Disabled` でスキップ中。M1 実装とは無関係。

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
  - requestTimeoutSeconds = 5（tick ループのブロック時間を抑えるため、Step5 で 10→5 に変更）
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
- M1 必要範囲のエンドポイントをサーバー側に実装する。

#### 確定設計方針

**1. リモートロックの表現（LockableResource 側）**
- `LockableResource` に `transient String remoteLockedBy`（lockId or null）フィールドを追加。
- LRM は `remoteLockedBy != null` のリソースを「使用中」と判定する。`RemoteLockRecord` の中身は知らない。

**2. Stapler ルーティング**
- `LockableResourcesRootAction.getDynamic("remote")` → `getDynamic("v1")` → `RemoteApiV1Action`
- `RemoteApiV1Action` に各エンドポイントを実装する。

**3. RemoteLockRecord の保管場所**
- `RemoteLockManager`（`@Extension`）を新規作成し、`ConcurrentHashMap<String, RemoteLockRecord>` で in-memory 管理。
- 永続化しない（Jenkins 再起動時は全レコードが消える）。
- 運用: 管理者が expose 対象リソースが healthy であることを確認してから `remoteApiEnabled = true` にする。

**4. マスタースイッチ / expose 設定**
- `LockableResourcesManager` に `remoteApiEnabled`（boolean、デフォルト false）と `exposeLabel`（String）を追加。
- `remoteApiEnabled = false` の場合、全エンドポイントが 403 を返す。

**5. 認証・認可**
- Jenkins 標準認証（API トークン）+ `Jenkins.READ` チェックのみ。
- 専用 Permission は M2 以降の検討とし、M1 では導入しない。

**6. Stale 検出と解放方針**
- `RemoteLockManager` のスケジューラスレッドで定期 scan し、STALE_THRESHOLD を超えたレコードを STALE マーク。
- Stale になったロックは自動解放しない（安全方向）。管理者が UI で手動 Unstale。
- Discovery / GET 系エンドポイントは read only（write 調停不要）。
- 並行性: `ConcurrentHashMap` + フィールドは `volatile`。

**並行性設計**
- `RemoteLockManager` は `ScheduledThreadPool(1)`（単一スレッド）で 1 秒周期の tick ループを持つ。
- tick 内で経過時間を見て必要なタスクを実行:
  - (client) 前回 poll から 3s 経過 → GET /acquire/{lockId}（アクティブロックごと）
  - (client) body 実行中 かつ 前回 heartbeat から 10s 経過 → POST /heartbeat（アクティブロックごと）
  - (client) Discovery: 前回から N 秒経過 → GET /resources
  - (server) 前回 Stale scan から STALE_THRESHOLD / 2 秒経過 → 全 RemoteLockRecord 走査
- 各タスクは `lastRunAt` タイムスタンプを持ち、tick 内で実行判断する。
- writer はこの 1 スレッドのみ → Discovery / GET 系は read only で調停不要。
- tick ループは単一スレッドのため、HTTP 呼び出しのブロック時間がそのまま tick 全体の遅延になる。
  この設計に合わせて `RemoteClientDefaults.DEFAULT_REQUEST_TIMEOUT_SECONDS` を 10 → 5 に変更する（Step5 コミットに含める）。

#### 実装対象エンドポイント

| メソッド | パス | 概要 |
|---|---|---|
| POST | `/lockable-resources/remote/v1/acquire` | acquire エンキュー、`{lockId}` を返す |
| GET  | `/lockable-resources/remote/v1/acquire/{lockId}` | 状態照会（QUEUED/ACQUIRED/SKIPPED/FAILED/EXPIRED） |
| POST | `/lockable-resources/remote/v1/lease/{lockId}/heartbeat` | heartbeat 更新、204 を返す |
| POST | `/lockable-resources/remote/v1/lease/{lockId}/release` | ロック解放、204 を返す |

#### 実装順序

1. `RemoteLockRecord` クラス新規作成
2. `RemoteLockManager` クラス新規作成（スケジューラ + record CRUD）
3. `LockableResource` に `remoteLockedBy` フィールド追加
4. `LockableResourcesManager` に `remoteApiEnabled` + `exposeLabel` 追加
5. `RemoteApiV1Action` 新規作成（エンドポイント実装）
6. `LockableResourcesRootAction` に `getDynamic` 追加

完了条件:
- local 側の `RemoteApiClient` から呼べる（3 controller 環境で動作確認）
- `remoteApiEnabled = false` のとき全エンドポイントが 403
- Stale マーク動作が確認できる

- [x] 実装完了
- [x] 単体確認完了

記録:
- 日付: 2026-05-14（2026-05-16 コードレビュー修正を amend）
- コミット: 8a8d816
- 変更ファイル:
  - src/main/java/.../remote/RemoteLockState.java (新規)
  - src/main/java/.../remote/RemoteLockRecord.java (新規)
  - src/main/java/.../remote/RemoteLockManager.java (新規)
  - src/main/java/.../remote/RemoteClientDefaults.java (編集: DEFAULT_REQUEST_TIMEOUT_SECONDS 10→5)
  - src/main/java/.../actions/RemoteApiV1Action.java (新規 + レビュー修正 amend)
  - src/main/java/.../LockableResource.java (編集: remoteLockedBy フィールド追加、isLocked() 更新)
  - src/main/java/.../LockableResourcesManager.java (編集: remoteApiEnabled + exposeLabel 追加)
  - src/main/java/.../actions/LockableResourcesRootAction.java (編集: getDynamic routing 追加)
  - src/test/resources/.../casc_expected_output.yml (編集: remoteApiEnabled: false 追加)
- 確認結果: `mvn test` で BUILD SUCCESS（Tests run: 261, Failures: 0, Errors: 0, Skipped: 1）。レビュー修正後も同結果を確認（2026-05-16）。
- 補足:
  - Extension index (`META-INF/annotations/hudson.Extension.txt`) が生成されないと Jenkins 起動時に @Extension クラスが未発見になり全テスト失敗する。`target/classes` を削除して強制再コンパイルすることで解消。
  - `mvn compile && mvn test` はこの問題を引き起こすため NG。`mvn test` のみを使う。
  - Stale 自動解放なし（安全方向）。STALE_THRESHOLD_MS=60000ms、TERMINAL_TTL_MS=120000ms。
  - 永続化なし（Jenkins 再起動時は全レコードが消える）。
  - 2026-05-16 コードレビュー指摘を amend で修正:
    - `exposeLabel` 未設定時に全リソースを公開していたバグを修正（opt-in 設計に合わせ未設定=全拒否）
    - `heartbeatIntervalSeconds` のサーバー側バリデーション追加（≤0 または非整数 → 400 INVALID_HEARTBEAT_INTERVAL）
    - POST /acquire レスポンスを 200 → 202 Accepted に修正
    - エラーコードを RESOURCE_NOT_FOUND → UNKNOWN_RESOURCE に統一（LRR-DESIGN 準拠）
  - remoteApiEnabled=false 時のステータスは 403 を正とする（LRR-DESIGN-j.md も同日修正済み）

---

### 6. 最小 UI/可視化（M1 で必要な範囲のみ）

スコープ確定（2026-05-16）:
- **6a**: `clientId` を `POST /acquire` に追加（クライアント送信 + サーバー受信・保存 + 設定 UI）
- **6b**: B-side LR ページ表示（サーバー側 LR 一覧に `clientId` を表示）

---

#### Step 6a: `clientId` 追加

目的:
- `POST /acquire` に送信元 Jenkins の識別子 `clientId` を持たせ、サーバー側でロック保有者を把握できるようにする。
- 管理者が明示設定できるフィールドを LRM に追加し、未設定時は `Jenkins.getRootUrl()` にフォールバックする。

実装内容:
- `RemoteLockRecord`: `clientId` フィールド追加（nullable）
- `RemoteLockManager.enqueue()`: シグネチャに `clientId` 追加
- `RemoteApiV1Action` (`POST /acquire`): `clientId` optional フィールドをパース・正規化・保存
- `RemoteApiClient.enqueueAcquire()`: `clientId` 引数追加、非 null 時のみリクエストボディに含める
- `LockableResourcesManager`: `clientId` 設定フィールド追加（`setClientId` / `getClientId` / `getEffectiveClientId`）、`readResolve()` に null 正規化追加
- `LockStepExecution`: `LockableResourcesManager.get().getEffectiveClientId()` を使用するよう変更
- `LockableResourcesManager/config.jelly`: "Remote Lockable Resources (Client)" セクションと `clientId` textbox 追加
- `LockableResourcesManager/config.properties`: UI ラベルキー追加
- `RemoteApiClientTest`: `enqueueAcquire()` 呼び出し箇所に `null` 引数追加
- `LRR-DESIGN-j.md`: `POST /acquire` 仕様・フロー図・セクション6 設定テーブルを更新

完了条件:
- `mvn test` が通る
- 設定 UI で `clientId` を入力・保存できる

- [x] 実装完了
- [x] `mvn test` 確認完了
- [x] コミット済み

記録:
- 日付: 2026-05-16
- コミット: f89330a
- 変更ファイル:
  - src/main/java/.../remote/RemoteLockRecord.java (編集)
  - src/main/java/.../remote/RemoteLockManager.java (編集)
  - src/main/java/.../actions/RemoteApiV1Action.java (編集)
  - src/main/java/.../remote/RemoteApiClient.java (編集)
  - src/main/java/.../LockableResourcesManager.java (編集: clientId フィールド追加)
  - src/main/java/.../LockStepExecution.java (編集: getEffectiveClientId() へ切替 + Jenkins import 削除)
  - src/main/resources/.../LockableResourcesManager/config.jelly (編集)
  - src/main/resources/.../LockableResourcesManager/config.properties (編集)
  - src/test/java/.../remote/RemoteApiClientTest.java (編集)
  - lrr-notes/dev/docs/LRR-DESIGN-j.md (編集)
- 確認結果: `mvn test` で BUILD SUCCESS（Tests run: 261, Failures: 0, Errors: 0, Skipped: 1, Total time: 13:05）。2026-05-16
- 補足: `getEffectiveClientId()` は `clientId` 設定が空なら `Jenkins.getRootUrl()` を返す（`@CheckForNull`）。UI は config.jelly に "Remote Lockable Resources (Client)" セクションを追加。

---

#### Step 6b: B-side LR ページ表示

目的:
- サーバー側 LR 一覧画面（Lockable Resources UI）に、remote lock 保有者の `clientId` を表示する。
- どの remote Jenkins がどのリソースをロックしているかを管理者が一目で把握できるようにする。

設計方針（確定）:
- 表示文字列: `Remote: <clientId>`（clientId が null の場合は `Remote: (unknown)`）
- データ取得: `LockableResource` に `getRemoteLockClientId()` メソッドを追加し、内部で `RemoteLockManager.get().getRecord(remoteLockedBy)` を呼ぶ
- `remoteLockedBy` が null（remote lock なし）のときは通常の "Locked by" 表示に fallback

実装内容:
- `LockableResource`: `getRemoteLockClientId()` メソッド追加
- `LockableResource` の表示 jelly（`index.jelly` または `index.groovy`）: `remoteLockedBy != null` の場合に `Remote: clientId` を表示
- `LRR-DESIGN-j.md`: Step 6a でセクション 6 に B-side 表示設計を追記済み

完了条件:
- LR 一覧で remote lock 保有者が "Remote: clientId" として確認できる
- `clientId` が null の場合に "Remote: (unknown)" が表示される

- [x] 実装完了
- [x] `mvn test` 確認完了
- [x] コミット済み

記録:
- 日付: 2026-05-17
- コミット: c2e9112
- 変更ファイル:
  - src/main/java/.../LockableResource.java (編集: getRemoteLockClientId() 追加)
  - src/main/resources/.../LockableResourcesRootAction/tableResources/table.jelly (編集: remote lock ケース追加)
  - src/main/resources/.../LockableResourcesRootAction/tableResources/table.properties (編集: resource.status.remoteLockedBy キー追加)
- 確認結果: `mvn test` で BUILD SUCCESS（Tests run: 261, Failures: 0, Errors: 0, Skipped: 1, Total time: 12:52）。2026-05-17
- 補足:
  - `getRemoteLockClientId()`: `remoteLockedBy == null` なら null 即返し、そうでなければ `RemoteLockManager.get().find(remoteLockedBy)` でレコードを検索して `clientId` を返す。レコードなし（再起動後等）は null。
  - `table.jelly`: status コンテンツの `j:choose` で remote lock ケースを job-locked ケースより前に配置。`resource.remoteLockedBy != null` で分岐し、`remoteLockClientId` が null の場合は `(unknown)` にフォールバック。
  - CSS クラス選択の `j:choose` は変更なし（`resource.locked == true` が既に `warning` に当たる）。

---

### 7. テスト（M1 の成立確認）

目的:
- 回帰防止のため、M1 の核心を自動テストで固定する。

優先テスト:
- `serverId` ありの分岐
- `serverId` なし既存挙動の維持
- remote acquire 成功/失敗の代表ケース
- `RemoteApiV1Action` HTTP レベルテスト（サーバー側エンドポイントの直接固定）:
  - `remoteApiEnabled=false` のとき全エンドポイントが 403 を返すこと
  - `exposeLabel` 未設定のとき POST /acquire が 404 UNKNOWN_RESOURCE を返すこと
  - `exposeLabel` 設定済みで対象ラベルなしリソースへの acquire が 404 UNKNOWN_RESOURCE を返すこと
  - `heartbeatIntervalSeconds` に不正値（0、負数、文字列）を送ると 400 INVALID_HEARTBEAT_INTERVAL を返すこと
  - 正常な acquire リクエストが 202 と lockId を返すこと

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
- 現在ステップ: Step 6b 完了済み（コミット `c2e9112`）
- 次アクション: Step 7（テスト）
- ブロッカー: なし

### ブランチ整理メモ

- 現 master に PR #1028（NodesMirror パッケージ修正）を cherry-pick 済み（コミット `e4f70c3`）
- feature ブランチは この cherry-pick 済み master で rebase 済み（2026-05-16）
- 本家 master に #1028 が取り込まれ次第、cherry-pick コミットを drop して rebase し直す
- **Step7 完了後の最終テスト実施時に下記 hash を実際のコミット hash へ更新すること**

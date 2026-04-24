# Lockable Resources Plugin アーキテクチャ解析

対象ブランチ: master  
対象パス: `lockable-resources-plugin/`  
目的: 実装把握 & 分散拡張の設計検討

---

## 目次

1. [全体構造の鳥瞰図](#1-全体構造の鳥瞰図)
2. [パッケージ構成とクラスの責務](#2-パッケージ構成とクラスの責務)
3. [データモデル詳細](#3-データモデル詳細)
4. [Pipeline での lock ステップ実行フロー](#4-pipeline-での-lock-ステップ実行フロー)
5. [待機キューの仕組み](#5-待機キューの仕組み)
6. [Freestyle ビルドとの連携](#6-freestyle-ビルドとの連携)
7. [UI と HTTP API](#7-ui-と-http-api)
8. [永続化の仕組み](#8-永続化の仕組み)
9. [Nodes Mirror 機能](#9-nodes-mirror-機能)
10. [同期・スレッド安全戦略](#10-同期スレッド安全戦略)

---

## 1. 全体構造の鳥瞰図

```mermaid
graph TB
    subgraph Jenkins_Core["Jenkins コア"]
        Queue["Queue（ビルドキュー）"]
        RunListener["RunListener"]
        GlobalConfig["GlobalConfiguration"]
    end

    subgraph Plugin["lockable-resources-plugin"]
        LRM["LockableResourcesManager\n（シングルトン・GlobalConfiguration）"]
        LR["LockableResource\n（データモデル）"]
        QCS["QueuedContextStruct\n（待機キュー要素）"]
        LRS["LockableResourcesStruct\n（リソース選択条件）"]

        subgraph Pipeline["Pipeline 連携"]
            LS["LockStep\n（DSL: lock(...)）"]
            LSE["LockStepExecution\n（実行エンジン）"]
        end

        subgraph QueuePkg["queue パッケージ"]
            LRL["LockRunListener\n（Freestyle 用）"]
            LRQ["LockableResourcesQueueTaskDispatcher\n（Freestyle 待機）"]
            LWTo["LockWaitTimeoutPeriodicWork\n（タイムアウト監視）"]
        end

        subgraph ActionsPkg["actions パッケージ"]
            LRRA["LockableResourcesRootAction\n（Web UI / REST API）"]
            LRBA["LockedResourcesBuildAction\n（ビルド付属ログ）"]
            RVA["ResourceVariableNameAction\n（変数名記録）"]
        end

        NM["NodesMirror\n（Node → Resource 自動同期）"]
    end

    subgraph Storage["永続化"]
        XML["org.jenkins...LockableResourcesManager.xml"]
    end

    subgraph User["利用者"]
        PipelineJob["Pipeline ジョブ\n（lock ステップ利用）"]
        FreeStyleJob["Freestyle ジョブ\n（RequiredResourcesProperty）"]
        JCasC["JCasC / YAML 設定"]
        WebUI["管理者 Web ブラウザ"]
        RestAPI["外部ツール / REST クライアント"]
    end

    PipelineJob -->|"lock(...) 呼び出し"| LS
    LS --> LSE
    LSE -->|"getAvailableResources()\nlock()\nunlockNames()"| LRM
    FreeStyleJob -->|"ビルド開始イベント"| LRL
    LRL --> LRM
    LRQ -->|"canRun() で待機判断"| LRM
    LWTo -->|"定期スキャン"| LRM
    LRM -->|"CRUD"| LR
    LRM -->|"待機管理"| QCS
    LRM -->|"save()"| XML
    XML -->|"load() on 起動"| LRM
    WebUI --> LRRA
    RestAPI --> LRRA
    LRRA --> LRM
    NM -->|"ComputerListener 経由"| LRM
    Queue --> LRQ
    RunListener --> LRL
    GlobalConfig --> LRM
    JCasC --> LRM
```

---

## 2. パッケージ構成とクラスの責務

```mermaid
classDiagram
    namespace root {
        class LockableResourcesManager {
            +List~LockableResource~ resources
            +List~QueuedContextStruct~ queuedContexts
            +lock() bool
            +unlock()
            +getAvailableResources() List
            +queueContext()
            +unqueueContext()
            +save()
            +load()
        }
        class LockableResource {
            +String name
            +List~String~ labelsAsList
            +String reservedBy
            +String buildExternalizableId
            +long queueItemId
            +boolean ephemeral
            +boolean isNode
            +String lockReason
            +isLocked() bool
            +isFree() bool
            +isReserved() bool
        }
        class LockStep {
            +String resource
            +String label
            +int quantity
            +String variable
            +boolean skipIfLocked
            +boolean inversePrecedence
            +int priority
            +String reason
            +long timeoutForAllocateResource
        }
        class LockStepExecution {
            +start() bool
            +stop()
            +proceed()
        }
    }
    namespace queue {
        class QueuedContextStruct {
            +StepContext context
            +List~LockableResourcesStruct~ resources
            +String variableName
            +boolean inversePrecedence
            +int priority
            +String reason
            +long waitTimeout
        }
        class LockableResourcesStruct {
            +List~String~ resources
            +String label
            +int quantity
        }
        class LockRunListener {
            +onStarted()
            +onCompleted()
        }
        class LockableResourcesQueueTaskDispatcher {
            +canRun() CauseOfBlockage
        }
        class LockWaitTimeoutPeriodicWork {
            +doRun()
        }
    }
    namespace actions {
        class LockableResourcesRootAction {
            +UNLOCK Permission
            +RESERVE Permission
            +STEAL Permission
            +VIEW Permission
            +QUEUE Permission
            +doReserve()
            +doUnreserve()
            +doUnlock()
            +doSteal()
        }
        class LockedResourcesBuildAction {
            +addLog()
        }
    }

    LockableResourcesManager "1" *-- "N" LockableResource
    LockableResourcesManager "1" *-- "N" QueuedContextStruct
    LockStep --> LockStepExecution : creates
    LockStepExecution --> LockableResourcesManager : calls
    QueuedContextStruct "1" *-- "N" LockableResourcesStruct
    LockRunListener --> LockableResourcesManager : calls
    LockableResourcesQueueTaskDispatcher --> LockableResourcesManager : calls
    LockWaitTimeoutPeriodicWork --> LockableResourcesManager : calls
    LockableResourcesRootAction --> LockableResourcesManager : calls
```

---

## 3. データモデル詳細

### 3.1 LockableResource のフィールドと状態

```mermaid
stateDiagram-v2
    [*] --> FREE : 作成（宣言型 or 自動生成）
    FREE --> QUEUED_FREESTYLE : Freestyle ジョブがキュー入り
    FREE --> LOCKED : lock() で即取得
    FREE --> RESERVED : 管理者が手動 reserve
    QUEUED_FREESTYLE --> LOCKED : ビルド開始時に取得
    QUEUED_FREESTYLE --> FREE : キュー取り消し
    LOCKED --> FREE : unlock / ビルド終了
    LOCKED --> STOLEN : 管理者が steal
    STOLEN --> FREE : unreserve
    RESERVED --> FREE : 管理者が unreserve
    RESERVED --> LOCKED : ビルドが reserve を解除して lock
    FREE --> [*] : ephemeral かつ unlock
```

| フィールド | 型 | 意味 |
|---|---|---|
| `name` | `String` | リソースの一意識別子（変更不可）|
| `labelsAsList` | `List<String>` | グループ化用ラベル |
| `reservedBy` | `String` | 手動 reserve 中のユーザー名 |
| `buildExternalizableId` | `String` | ロック中の Run の ID（永続化用）|
| `queueItemId` | `long` | Freestyle キュー待ち中の Item ID |
| `ephemeral` | `boolean` | true = スコープ外 lock 時に自動生成、unlock 時に自動削除 |
| `isNode` | `transient boolean` | Jenkins Node から自動ミラーされた仮想リソース |
| `lockReason` | `String` | lock ステップで指定された理由文字列 |
| `stolen` | `boolean` | 管理者が奪取した場合のフラグ |

### 3.2 クラスの継承関係

```mermaid
classDiagram
    class Serializable
    class AbstractDescribableImpl
    class GlobalConfiguration
    class AbstractStepExecutionImpl
    class Step
    class RootAction
    class RunListener
    class ComputerListener
    class AsyncPeriodicWork

    AbstractDescribableImpl <|-- LockableResource
    GlobalConfiguration <|-- LockableResourcesManager
    AbstractStepExecutionImpl <|-- LockStepExecution
    Step <|-- LockStep
    RootAction <|-- LockableResourcesRootAction
    RunListener <|-- LockRunListener
    ComputerListener <|-- NodesMirror
    AsyncPeriodicWork <|-- LockWaitTimeoutPeriodicWork
    Serializable <|-- LockableResource
    Serializable <|-- LockStepExecution
```

---

## 4. Pipeline での lock ステップ実行フロー

### 4.1 取得成功パス

```mermaid
sequenceDiagram
    participant P as Pipeline DSL
    participant LS as LockStep
    participant LSE as LockStepExecution
    participant LRM as LockableResourcesManager
    participant LR as LockableResource

    P->>LS: lock(resource:"foo", reason:"test")
    LS->>LSE: start()
    LSE->>LRM: synchronized(syncResources)
    LSE->>LRM: createResource("foo") ← 存在しなければ自動生成
    LSE->>LRM: getAvailableResources(resourceHolderList, strategy)
    LRM->>LR: isFree() × 全候補
    LRM-->>LSE: available = [foo]
    LSE->>LRM: lock(available, run, reason)
    LRM->>LR: setBuildExternalizableId(build.id)
    LRM->>LR: setLockReason(reason)
    LRM-->>LSE: true
    LSE->>LSE: proceed(lockedResources, context, ...)
    Note over LSE: BodyInvoker.start() で<br/>クリティカルセクションを非同期実行
    Note over LSE: Callback.finished() が<br/>ボディ終了時に呼ばれる
    LSE->>LRM: unlockNames(resourceNames, build)
    LRM->>LR: 状態クリア
    LRM->>LRM: tryNextContext() で待機中を再評価
```

### 4.2 取得失敗→待機→再取得パス

```mermaid
sequenceDiagram
    participant LSE as LockStepExecution (B)
    participant LRM as LockableResourcesManager
    participant QCS as QueuedContextStruct

    LSE->>LRM: getAvailableResources(...)
    LRM-->>LSE: empty (リソース使用中)
    LSE->>LRM: queueContext(context, resourceHolderList, ...)
    LRM->>QCS: new QueuedContextStruct を queuedContexts に挿入
    Note over LSE: start() が false を返し<br/>Pipeline はここで一時停止

    Note over LRM: 別ビルドが unlock を呼ぶ
    LRM->>LRM: freeResources()
    LRM->>LRM: tryNextContext()
    LRM->>QCS: queuedContexts を先頭から評価
    LRM->>LRM: getAvailableResources() で候補チェック
    LRM->>LRM: lock(requiredResource, build)
    LRM->>LSE: LockStepExecution.proceed() を直接呼び出し
    Note over LSE: クリティカルセクション再開
```

---

## 5. 待機キューの仕組み

```mermaid
graph TB
    A["queueContext() 呼び出し"]
    B{"inversePrecedence\nor priority?"}
    C["末尾に追加\n（FIFO デフォルト）"]
    D["優先挿入位置を計算\n（priority 降順・同値は後）"]
    E["queuedContexts に挿入"]
    F["tryNextContext() ループ"]
    G{"先頭エントリの\nresource は空き?"}
    H["lock 取得\nproced() 呼び出し"]
    I["次のエントリへ"]
    J["全エントリ評価完了"]

    A --> B
    B -->|"通常"| C
    B -->|"inversePrecedence / priority"| D
    C --> E
    D --> E
    E --> F
    F --> G
    G -->|"Yes"| H
    H --> F
    G -->|"No"| I
    I --> G
    G -->|"全て評価済"| J
```

**timeout 付き待機（LockWaitTimeoutPeriodicWork）:**

```mermaid
sequenceDiagram
    participant PW as LockWaitTimeoutPeriodicWork
    participant LRM as LockableResourcesManager
    participant QCS as QueuedContextStruct

    loop 定期実行（nextTimeoutTask にスケジュール）
        PW->>LRM: checkWaitTimeouts()
        LRM->>QCS: 各エントリの waitTimeout を確認
        alt タイムアウト超過
            LRM->>QCS: context.onFailure(LockWaitTimeoutException)
            LRM->>LRM: unqueueContext()
        end
    end
```

---

## 6. Freestyle ビルドとの連携

Freestyle は Pipeline と異なり、**Jenkins の標準ビルドキュー** を経由してリソース管理を行います。

```mermaid
sequenceDiagram
    participant J as Jenkins Queue
    participant LRQ as LockableResourcesQueueTaskDispatcher
    participant LRL as LockRunListener
    participant LRM as LockableResourcesManager

    J->>LRQ: canRun(item) を呼ぶ
    LRQ->>LRM: getAvailableResources(項目の RequiredResourcesProperty)
    alt リソース空きなし
        LRM-->>LRQ: empty
        LRQ-->>J: CauseOfBlockage（ブロック理由を返す）
        Note over J: ビルドはキューに留まる
    else リソース空きあり
        LRM-->>LRQ: available
        LRM->>LRM: queue(resources, queueItemId) でロック予約
        LRQ-->>J: null（実行許可）
    end

    J->>LRL: onStarted(build)
    LRL->>LRM: lock(queuedResources, build)
    Note over LRM: キュー予約 → 実際の lock に昇格

    J->>LRL: onCompleted(build)
    LRL->>LRM: unlockBuild(build)
    LRM->>LRM: tryNextContext()
```

---

## 7. UI と HTTP API

### 7.1 URL 構成

```mermaid
graph TD
    ROOT["/jenkins/lockable-resources/"]
    ROOT --> INDEX["index.jelly\n（リソース一覧・ラベル一覧・待機キュー）"]
    ROOT --> API["/api/json\n（REST API: getResources() を @Exported で公開）"]
    ROOT --> RESERVE["doReserve()\nPOST /reserve"]
    ROOT --> UNRESERVE["doUnreserve()\nPOST /unreserve"]
    ROOT --> UNLOCK["doUnlock()\nPOST /unlock"]
    ROOT --> STEAL["doSteal()\nPOST /steal"]
    ROOT --> NOTE["doChangeNote()\nPOST /changeNote"]
    ROOT --> QORDER["doChangeQueueOrder()\nPOST /changeQueueOrder"]
```

### 7.2 権限モデル

```mermaid
graph LR
    PG["PermissionGroup\n（LockableResourcesManager）"]
    PG --> VIEW["VIEW\n（画面表示）"]
    PG --> UNLOCK["UNLOCK\n（手動 unlock）"]
    PG --> RESERVE["RESERVE\n（手動 reserve）"]
    PG --> STEAL["STEAL\n（使用中を奪取）"]
    PG --> QUEUE["QUEUE\n（待機順序変更）"]

    VIEW -->|"デフォルト親権限"| ADMINISTER["Jenkins.ADMINISTER"]
    UNLOCK --> ADMINISTER
    RESERVE --> ADMINISTER
    STEAL --> ADMINISTER
    QUEUE --> ADMINISTER
```

**分散化における注意点:**  
`LockableResourcesRootAction` は `RootAction`（認証済み）として実装されています。  
`UnprotectedRootAction` ではなく、通常の認証フローに乗ります。  
外部 Jenkins からエンドポイントを呼ぶ場合は、Jenkins の API Token 認証ヘッダが必要です。

---

## 8. 永続化の仕組み

```mermaid
graph LR
    subgraph 起動時
        A["Jenkins 起動"]
        B["LockableResourcesManager コンストラクタ"]
        C["GlobalConfiguration.load()"]
        D["XStream デシリアライズ"]
        E["resources リスト復元"]
        A --> B --> C --> D --> E
    end

    subgraph 保存時
        F["LRM の変更操作"]
        G{"asyncSaveEnabled?"}
        H["savePending = true\nScheduledExecutor に遅延保存"]
        I["GlobalConfiguration.save() 即時"]
        J["XStream シリアライズ"]
        K["org.jenkins...LockableResourcesManager.xml"]
        F --> G
        G -->|"true（デフォルト）"| H --> J
        G -->|"false"| I --> J
        J --> K
    end
```

**非同期保存の設計（saveCoalesceMs: デフォルト 1000ms）:**

lock が頻繁に起きる環境でのディスク I/O バーストを防ぐため、`AtomicBoolean savePending` + `ScheduledExecutor` でコアレスされます。  
システムプロパティ `org.jenkins.plugins.lockableresources.ASYNC_SAVE=false` で無効化できます。

---

## 9. Nodes Mirror 機能

```mermaid
sequenceDiagram
    participant J as Jenkins
    participant NM as NodesMirror（ComputerListener）
    participant LRM as LockableResourcesManager

    J->>NM: @Initializer(after=JOB_LOADED) → createNodeResources()
    NM->>J: getNodes() 一覧取得
    loop 各 Node
        NM->>LRM: fromName(node.name) で既存チェック
        alt 未存在
            NM->>LRM: addResource(new LockableResource(name))
        end
        NM->>LRM: resource.setLabels(assignedLabels)\nsetNodeResource(true)
    end
    NM->>NM: deleteNotExistingNodes()（削除済み Node の resource 掃除）

    Note over NM: onConfigurationChange() でも同様に mirrorNodes() を呼ぶ
```

有効化: `-Dorg.jenkins.plugins.lockableresources.ENABLE_NODE_MIRROR=true`  
用途: Jenkins Agent ノード自体を lockable resource として管理する（例: 特定 node の独占使用）

---

## 10. 同期・スレッド安全戦略

```mermaid
graph TB
    A["syncResources\n（静的 Object ロック）"]
    A --> B["LockableResourcesManager 内の\nほぼ全書き込み操作"]
    A --> C["LockRunListener.onStarted()\nonCompleted()"]
    A --> D["LockStepExecution.start()\n（synchronized ブロック内）"]
    A --> E["LockableResourcesRootAction\nの各 do〇〇 メソッド"]

    subgraph キャッシュ
        F["cachedCandidates\n（Guava Cache, 5分 TTL）"]
        G["scriptCache / labelCache\n（LockableResource per-instance）"]
    end
    B --> F
    B --> G
```

| 対象 | 方針 |
|---|---|
| リソースリスト読み書き | `synchronized (syncResources)` |
| 候補リソースキャッシュ | `Guava Cache`（5分 TTL、queueItemId がキー）|
| Groovy スクリプト結果 | per-resource `ConcurrentHashMap` + TTL（デフォルト 30s）|
| 保存処理 | `AtomicBoolean savePending` + coalesce |

---

> **メモ:** このドキュメントは master ブランチ（2.19 系）のコードを元に作成。  
> 参照ファイル:  
> - `LockableResource.java`  
> - `LockableResourcesManager.java`  
> - `LockStepExecution.java`  
> - `LockStep.java`  
> - `actions/LockableResourcesRootAction.java`  
> - `queue/LockRunListener.java`  
> - `queue/LockableResourcesQueueTaskDispatcher.java`  
> - `nodes/NodesMirror.java`

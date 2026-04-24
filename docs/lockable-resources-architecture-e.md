# Lockable Resources Plugin Architectural Analysis

Target branch: master  
Target path: `lockable-resources-plugin/`  
Purpose: to document implementation details and provide study material for future extension design.

---

## Table of Contents

1. [High-Level Architectural Overview](#1-high-level-architectural-overview)
2. [Package Structure and Class Responsibilities](#2-package-structure-and-class-responsibilities)
3. [Data Model Details](#3-data-model-details)
4. [Execution Flow of the Pipeline lock Step](#4-execution-flow-of-the-pipeline-lock-step)
5. [How the Waiting Queue Works](#5-how-the-waiting-queue-works)
6. [Integration with Freestyle Builds](#6-integration-with-freestyle-builds)
7. [UI and HTTP API](#7-ui-and-http-api)
8. [Persistence Mechanism](#8-persistence-mechanism)
9. [Nodes Mirror Feature](#9-nodes-mirror-feature)
10. [Synchronization and Thread-Safety Strategy](#10-synchronization-and-thread-safety-strategy)

---

## 1. High-Level Architectural Overview

```mermaid
graph TB
    subgraph Jenkins_Core["Jenkins Core"]
        Queue["Queue (build queue)"]
        RunListener["RunListener"]
        GlobalConfig["GlobalConfiguration"]
    end

    subgraph Plugin["lockable-resources-plugin"]
        LRM["LockableResourcesManager\n(singleton / GlobalConfiguration)"]
        LR["LockableResource\n(data model)"]
        QCS["QueuedContextStruct\n(wait queue entry)"]
        LRS["LockableResourcesStruct\n(resource selection criteria)"]

        subgraph Pipeline["Pipeline integration"]
            LS["LockStep\n(DSL: lock(...))"]
            LSE["LockStepExecution\n(execution engine)"]
        end

        subgraph QueuePkg["queue package"]
            LRL["LockRunListener\n(for Freestyle jobs)"]
            LRQ["LockableResourcesQueueTaskDispatcher\n(Freestyle queue gating)"]
            LWTo["LockWaitTimeoutPeriodicWork\n(timeout watcher)"]
        end

        subgraph ActionsPkg["actions package"]
            LRRA["LockableResourcesRootAction\n(Web UI / REST API)"]
            LRBA["LockedResourcesBuildAction\n(build-level lock log)"]
            RVA["ResourceVariableNameAction\n(variable name tracking)"]
        end

        NM["NodesMirror\n(Node -> Resource auto-sync)"]
    end

    subgraph Storage["Persistence"]
        XML["org.jenkins...LockableResourcesManager.xml"]
    end

    subgraph User["Users"]
        PipelineJob["Pipeline job\n(using lock step)"]
        FreeStyleJob["Freestyle job\n(RequiredResourcesProperty)"]
        JCasC["JCasC / YAML configuration"]
        WebUI["Admin web browser"]
        RestAPI["External tool / REST client"]
    end

    PipelineJob -->|"calls lock(...)"| LS
    LS --> LSE
    LSE -->|"getAvailableResources()\nlock()\nunlockNames()"| LRM
    FreeStyleJob -->|"build start event"| LRL
    LRL --> LRM
    LRQ -->|"canRun() decides waiting"| LRM
    LWTo -->|"periodic scan"| LRM
    LRM -->|"CRUD"| LR
    LRM -->|"waiting management"| QCS
    LRM -->|"save()"| XML
    XML -->|"load() on startup"| LRM
    WebUI --> LRRA
    RestAPI --> LRRA
    LRRA --> LRM
    NM -->|"via ComputerListener"| LRM
    Queue --> LRQ
    RunListener --> LRL
    GlobalConfig --> LRM
    JCasC --> LRM
```

---

## 2. Package Structure and Class Responsibilities

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

## 3. Data Model Details

### 3.1 LockableResource Fields and State

```mermaid
stateDiagram-v2
    [*] --> FREE : created (declared or auto-created)
    FREE --> QUEUED_FREESTYLE : Freestyle job enters queue
    FREE --> LOCKED : acquired by lock()
    FREE --> RESERVED : manually reserved by admin
    QUEUED_FREESTYLE --> LOCKED : acquired when build starts
    QUEUED_FREESTYLE --> FREE : queue canceled
    LOCKED --> FREE : unlock / build finished
    LOCKED --> STOLEN : stolen by admin
    STOLEN --> FREE : unreserve
    RESERVED --> FREE : unreserve by admin
    RESERVED --> LOCKED : build clears reservation and locks it
    FREE --> [*] : ephemeral and then unlocked
```

| Field | Type | Meaning |
|---|---|---|
| `name` | `String` | unique resource identifier (immutable) |
| `labelsAsList` | `List<String>` | labels used for grouping |
| `reservedBy` | `String` | username that currently holds a manual reservation |
| `buildExternalizableId` | `String` | ID of the Run currently locking the resource (for persistence) |
| `queueItemId` | `long` | queue item ID while waiting in Freestyle queue |
| `ephemeral` | `boolean` | true = auto-created outside declared config, auto-removed after unlock |
| `isNode` | `transient boolean` | virtual resource mirrored from a Jenkins Node |
| `lockReason` | `String` | reason string provided by the lock step |
| `stolen` | `boolean` | flag indicating the resource was forcefully taken by an admin |

### 3.2 Class Inheritance Relationships

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

## 4. Execution Flow of the Pipeline lock Step

### 4.1 Successful Acquisition Path

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
    LSE->>LRM: createResource("foo") if it does not exist
    LSE->>LRM: getAvailableResources(resourceHolderList, strategy)
    LRM->>LR: isFree() for all candidates
    LRM-->>LSE: available = [foo]
    LSE->>LRM: lock(available, run, reason)
    LRM->>LR: setBuildExternalizableId(build.id)
    LRM->>LR: setLockReason(reason)
    LRM-->>LSE: true
    LSE->>LSE: proceed(lockedResources, context, ...)
    Note over LSE: BodyInvoker.start() runs the<br/>critical section asynchronously
    Note over LSE: Callback.finished() is invoked<br/>after the body completes
    LSE->>LRM: unlockNames(resourceNames, build)
    LRM->>LR: clear state
    LRM->>LRM: re-evaluate waiting entries with tryNextContext()
```

### 4.2 Failure -> Wait -> Retry Path

```mermaid
sequenceDiagram
    participant LSE as LockStepExecution (B)
    participant LRM as LockableResourcesManager
    participant QCS as QueuedContextStruct

    LSE->>LRM: getAvailableResources(...)
    LRM-->>LSE: empty (resource already in use)
    LSE->>LRM: queueContext(context, resourceHolderList, ...)
    LRM->>QCS: insert a new QueuedContextStruct into queuedContexts
    Note over LSE: start() returns false and<br/>the Pipeline pauses here

    Note over LRM: another build calls unlock
    LRM->>LRM: freeResources()
    LRM->>LRM: tryNextContext()
    LRM->>QCS: evaluate queuedContexts from the front
    LRM->>LRM: check candidates with getAvailableResources()
    LRM->>LRM: lock(requiredResource, build)
    LRM->>LSE: call LockStepExecution.proceed() directly
    Note over LSE: critical section resumes
```

---

## 5. How the Waiting Queue Works

The queue is not a simple FIFO in all cases. It supports priority and inverse precedence while still trying to avoid starvation.

```mermaid
graph TB
    A["queueContext() is called"]
    B{"inversePrecedence\nor priority?"}
    C["append to tail\n(default FIFO)"]
    D["calculate insertion point\n(priority descending; equal stays later)"]
    E["insert into queuedContexts"]
    F["tryNextContext() loop"]
    G{"is the resource for the\nfront entry available?"}
    H["acquire lock\ncall proceed()"]
    I["move to next entry"]
    J["all entries evaluated"]

    A --> B
    B -->|"normal"| C
    B -->|"inversePrecedence / priority"| D
    C --> E
    D --> E
    E --> F
    F --> G
    G -->|"Yes"| H
    H --> F
    G -->|"No"| I
    I --> G
    G -->|"evaluation finished"| J
```

**Timeout handling while waiting (`LockWaitTimeoutPeriodicWork`):**

```mermaid
sequenceDiagram
    participant PW as LockWaitTimeoutPeriodicWork
    participant LRM as LockableResourcesManager
    participant QCS as QueuedContextStruct

    loop periodic execution (scheduled by nextTimeoutTask)
        PW->>LRM: checkWaitTimeouts()
        LRM->>QCS: inspect waitTimeout for each entry
        alt timeout exceeded
            LRM->>QCS: context.onFailure(LockWaitTimeoutException)
            LRM->>LRM: unqueueContext()
        end
    end
```

---

## 6. Integration with Freestyle Builds

Freestyle builds rely on the standard Jenkins queue model, instead of the Pipeline pause/resume mechanism.

```mermaid
sequenceDiagram
    participant J as Jenkins Queue
    participant LRQ as LockableResourcesQueueTaskDispatcher
    participant LRL as LockRunListener
    participant LRM as LockableResourcesManager

    J->>LRQ: call canRun(item)
    LRQ->>LRM: getAvailableResources(from RequiredResourcesProperty)
    alt no free resource
        LRM-->>LRQ: empty
        LRQ-->>J: CauseOfBlockage
        Note over J: build remains in queue
    else resource available
        LRM-->>LRQ: available
        LRM->>LRM: reserve lock via queue(resources, queueItemId)
        LRQ-->>J: null (allow execution)
    end

    J->>LRL: onStarted(build)
    LRL->>LRM: lock(queuedResources, build)
    Note over LRM: queue reservation is then promoted to an actual lock

    J->>LRL: onCompleted(build)
    LRL->>LRM: unlockBuild(build)
    LRM->>LRM: tryNextContext()
```

---

## 7. UI and HTTP API

### 7.1 URL Structure

```mermaid
graph TD
    ROOT["/jenkins/lockable-resources/"]
    ROOT --> INDEX["index.jelly\n(resource list, label list, waiting queue)"]
    ROOT --> API["/api/json\n(REST API exposing getResources() via @Exported)"]
    ROOT --> RESERVE["doReserve()\nPOST /reserve"]
    ROOT --> UNRESERVE["doUnreserve()\nPOST /unreserve"]
    ROOT --> UNLOCK["doUnlock()\nPOST /unlock"]
    ROOT --> STEAL["doSteal()\nPOST /steal"]
    ROOT --> NOTE["doChangeNote()\nPOST /changeNote"]
    ROOT --> QORDER["doChangeQueueOrder()\nPOST /changeQueueOrder"]
```

### 7.2 Permission Model

```mermaid
graph LR
    PG["PermissionGroup\n(LockableResourcesManager)"]
    PG --> VIEW["VIEW\n(display page)"]
    PG --> UNLOCK["UNLOCK\n(manual unlock)"]
    PG --> RESERVE["RESERVE\n(manual reserve)"]
    PG --> STEAL["STEAL\n(forcefully take from current holder)"]
    PG --> QUEUE["QUEUE\n(change waiting order)"]

    VIEW -->|"default parent permission"| ADMINISTER["Jenkins.ADMINISTER"]
    UNLOCK --> ADMINISTER
    RESERVE --> ADMINISTER
    STEAL --> ADMINISTER
    QUEUE --> ADMINISTER
```

**Important note for potential distributed use:**  
`LockableResourcesRootAction` is implemented as a `RootAction` (authenticated), not an `UnprotectedRootAction`.  
This keeps it inside the standard Jenkins authentication flow.  
If another Jenkins instance calls these endpoints, API token-based authentication is required.

---

## 8. Persistence Mechanism

The plugin persists state through Jenkins `GlobalConfiguration`, with optional asynchronous save coalescing to reduce disk I/O churn.

```mermaid
graph LR
    subgraph Startup
        A["Jenkins startup"]
        B["LockableResourcesManager constructor"]
        C["GlobalConfiguration.load()"]
        D["XStream deserialization"]
        E["restore resources list"]
        A --> B --> C --> D --> E
    end

    subgraph Save
        F["state-changing operation in LRM"]
        G{"asyncSaveEnabled?"}
        H["savePending = true\ndelayed save via ScheduledExecutor"]
        I["GlobalConfiguration.save() immediately"]
        J["XStream serialization"]
        K["org.jenkins...LockableResourcesManager.xml"]
        F --> G
        G -->|"true (default)"| H --> J
        G -->|"false"| I --> J
        J --> K
    end
```

**Asynchronous save design (`saveCoalesceMs`: default `1000ms`):**

To avoid bursts of disk I/O in environments with frequent lock/unlock activity, save operations are coalesced using `AtomicBoolean savePending` and a `ScheduledExecutor`.  
This can be disabled with the system property `org.jenkins.plugins.lockableresources.ASYNC_SAVE=false`.

---

## 9. Nodes Mirror Feature

When enabled, this feature mirrors Jenkins nodes as lockable resources so node-level exclusivity can be modeled through the same lock mechanism.

```mermaid
sequenceDiagram
    participant J as Jenkins
    participant NM as NodesMirror (ComputerListener)
    participant LRM as LockableResourcesManager

    J->>NM: @Initializer(after=JOB_LOADED) -> createNodeResources()
    NM->>J: getNodes()
    loop each Node
        NM->>LRM: check existing resource with fromName(node.name)
        alt not found
            NM->>LRM: addResource(new LockableResource(name))
        end
        NM->>LRM: resource.setLabels(assignedLabels)\nsetNodeResource(true)
    end
    NM->>NM: deleteNotExistingNodes() (cleanup removed nodes)

    Note over NM: onConfigurationChange() also calls mirrorNodes()
```

Enabled by: `-Dorg.jenkins.plugins.lockableresources.ENABLE_NODE_MIRROR=true`  
Use case: treat Jenkins agent nodes themselves as lockable resources (for example, exclusive use of a specific node).

---

## 10. Synchronization and Thread-Safety Strategy

Thread safety is centered on a shared monitor (`syncResources`) combined with targeted caches to keep lock checks efficient.

```mermaid
graph TB
    A["syncResources\n(static object lock)"]
    A --> B["nearly all write operations\ninside LockableResourcesManager"]
    A --> C["LockRunListener.onStarted()\nonCompleted()"]
    A --> D["LockStepExecution.start()\n(inside synchronized block)"]
    A --> E["do* methods in\nLockableResourcesRootAction"]

    subgraph Cache
        F["cachedCandidates\n(Guava Cache, 5 min TTL)"]
        G["scriptCache / labelCache\n(per LockableResource instance)"]
    end
    B --> F
    B --> G
```

| Target | Strategy |
|---|---|
| Resource list read/write | `synchronized (syncResources)` |
| Candidate resource cache | `Guava Cache` (5 min TTL, keyed by queueItemId) |
| Groovy script result cache | per-resource `ConcurrentHashMap` + TTL (default 30s) |
| Save processing | `AtomicBoolean savePending` + coalescing |

---

> **Note:** This document is based on the master-branch codebase (2.19 line).  
> Main referenced files:  
> - `LockableResource.java`  
> - `LockableResourcesManager.java`  
> - `LockStepExecution.java`  
> - `LockStep.java`  
> - `actions/LockableResourcesRootAction.java`  
> - `queue/LockRunListener.java`  
> - `queue/LockableResourcesQueueTaskDispatcher.java`  
> - `nodes/NodesMirror.java`

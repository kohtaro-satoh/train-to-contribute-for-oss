# Remote Lock — 背景と動機

> 🧪 Practice / Draft. 本番設計ではなく、練習用の草案です。
> 本家 `jenkinsci/lockable-resources-plugin` に提案する前の勉強メモとして書いています。

Upstream 要望: `https://github.com/jenkinsci/lockable-resources-plugin/issues/321`

## 1. このドキュメントの目的

- なぜ「別の Jenkins controller が管理するリソースを `lock()` したい」のか、
  その動機を共有する。
- 最終的に本家プラグインへ提案するための土台にする。
- 議論が発散しないように、**スコープの外**も明示する。

このドキュメントは仕様そのものではなく、**なぜこの仕様になったか**を残すものです。
仕様自体は親 Epic 本文および sub-Epic 側に書きます。

## 2. 出発点（#321 で挙がっていた要望）

`lockable-resources-plugin` の issue #321 では、大まかに次のような要望が挙がっていました。

- Jenkins の規模が大きくなってきて、1 インスタンスでの運用が厳しくなりつつある。
- 複数の Jenkins controller に分割したいが、**一部のリソースは複数 controller で共有したい**。
  - 例: controller A のジョブが resource `r1` を使っている間は、
    controller B のジョブは `r1` の解放を待つ。
- うまくいけば冗長化（24/7 運用）の土台にもなる。

つまり「**複数 Jenkins 間でロック可能リソースを共有したい**」というのが
元の要望のコアです。

#321 のコメント欄では、"lockable-master / lockable-slave" という
専用インスタンスを立てる案や、複数 master で冗長化する案なども
挙がっていました。

## 3. この提案のスタンス（なぜ "federation" と呼ばないか）

最初は「federation support」として話を広げていましたが、
設計を詰めていくうちに、次の理由で **最小限のリモートロック拡張**
から入るほうが健全だと判断しました。

- 「federation」という言葉はスコープが広すぎる。
  - 透過的なマルチコントローラ、レプリケーション、HA、
    フェイルオーバーまで含意されやすい。
- 本当に必要なのは、まず **「別の controller のロックを取れる」** こと。
  それ以外は段階的にで良い。
- ロックは「排他」が本質なので、**曖昧な挙動で取れてしまう**ことが最大の事故源。
  最初から大きく作ると、この事故源が増える。

したがって、このシリーズでは次のスタンスで進めます:

- **明示的**: ルーティングは `serverId: 'Remote1'` のように呼び出し側が指定する。
- **軽量**: 新しいサブシステム・クラスタ管理・分散合意は入れない。
- **安全優先**: 不確かな時は「取らない／解放しない」に倒す。

広義の federation（`serverId: 'any'`、multi-master、レプリケーション等）は
**Future work** として、今回の親 Epic の範囲外に置きます。

## 4. なぜ今これを議論するのか

現場の実感として、次のような状況が中小規模の Jenkins 運用で増えています。

- チーム / 部署 / プロダクトごとに Jenkins を分けて運用している。
- しかし **物理デバイスや共有テスト環境は分割できない**。
  - 例: HW ボード、計測器、ライセンスが有限な外部ツール、
    共有ステージング環境 など。
- 1 つの巨大 Jenkins を共有するのはメンテナンス的に辛い。
  だが、共有したい「物」はある。

ここを橋渡しするのが本提案の狙いです。
「**Jenkins は分割しつつ、一部の物理/論理リソースだけ共有する**」という運用を
ネイティブにサポートします。

## 5. 類似機能・先行事例との違い

参考にした/比較した先行事例:

- `node-sharing` / `node-sharing-orchestrator`:
  - 「Jenkins 間でノード（エージェント）を共有する」方向の仕組み。
  - 本提案は対象が異なり、共有したいのは **エージェント** ではなく
    **排他的に使いたいリソース（`LockableResource`）** である。
- Signiant/super-jenkins のような multi-master 構成案:
  - 複数の Jenkins を束ねるアイデアは近いが、
    ロック個別のセマンティクスには踏み込んでいない。
- `vra` プラグイン等の外部 REST クライアント実装:
  - 「Jenkins から外部 REST を長く呼び続ける」実装パターンとして参考にした。

本提案の違いは、**「ロックの正しさ」を最優先**に据えて、
通信トポロジ・失敗時挙動・リソース作成ポリシーを
意図的に狭く・固く作る点にあります。

## 6. 本提案がやること／やらないこと（概要）

詳細は親 Epic を参照。概要だけ再掲します。

### やること（初期スコープ）

- `lock(..., serverId: 'Remote1') { body }` で、
  別の Jenkins controller が管理するリソースをロックする。
- body はローカル側で実行する（移動しない）。
- 通信は **ローカル → リモート のみ**。
- REST + API token 認証。
- 取得結果は GET で一貫して観測する（short-polling）。
- 事前登録されていない resource / label は **拒否**（自動作成しない）。
- 通信断では **自動解放しない**（fail-closed）。

### やらないこと（Future work）

- `serverId: 'any'` / 複数サーバ間の自動ルーティング。
- Push 型（リモート→ローカル）の通知。
- レプリケーション、分散合意、HA オーケストレーション。
- Freestyle プロジェクト対応（Phase 1 では Pipeline のみ）。

## 7. 参考リンク

- 本家 issue #321（要望元）
- #321 内のコメント（"lockable-master / lockable-slave" アイデア）
- `node-sharing` プラグイン
- `vra` プラグインの REST クライアント実装
- 親 Epic（本リポジトリ）: Remote lockable resources (explicit `serverId` routing)
- `docs-j/remote-lock-usecase-j.md`（このドキュメントと対になるユースケース集）
- `docs-j/remote-lock-design-notes-j.md`（設計上の判断メモ）

## 8. TODO / 要検討

- `TODO:` 先行プラグインの挙動を一次情報で確認し直す（`node-sharing` 等）。
- `要検討:` 「federation」という語を完全に避けるか、
  "narrow federation" のようにニュアンスを残すか。
- `TODO:` upstream に持ち込むときの英訳版をどこに置くか
  （本リポ `docs/en/` か、本家 PR に直接同梱か）。

Follow-up to #321 — proposes a concrete, minimal-surface design for the
"synchronize locked resources between multiple Jenkins instances" idea.

## Summary
(Epic 本文の ## Summary をそのまま)

## Goals
(Epic 本文の ## Goals をそのまま)

## Non-goals (initial)
(Epic 本文の ## Non-goals をそのまま)

## High-level design
(Epic 本文の ## High-level design をそのまま)

### Mutual sharing via multiple independent one-way relations
(該当サブセクションをそのまま)

### REST endpoints (v1)
(そのまま)

### Client loop (reference)
(そのまま。コードブロックも ``` で囲めばOK)

## Background & motivation
- [Background & motivation](https://github.com/kohtaro-satoh/train-to-contribute-for-oss/blob/main/docs-e/remote-lock-background-e.md)
- [Realworld usecase (small/medium scale)](https://github.com/kohtaro-satoh/train-to-contribute-for-oss/blob/main/docs-e/remote-lock-usecase-e.md)
- [Design rationale](https://github.com/kohtaro-satoh/train-to-contribute-for-oss/blob/main/docs-e/remote-lock-design-notes-e.md)
- [Existing plugin architecture notes](https://github.com/kohtaro-satoh/train-to-contribute-for-oss/blob/main/docs-e/lockable-resources-architecture-e.md)

(Japanese originals: [`docs-j/`](https://github.com/kohtaro-satoh/train-to-contribute-for-oss/tree/main/docs-j))

## Phases (sub-Epics, to be filed)
- [ ] Phase 1 — Remote lock via REST (safety-first, short-polling)
- [ ] Phase 2 — Remote resource view (read-only mirror)
- [ ] Phase 3 — Ops & hardening

> Sub-Epic issues will be filed once the high-level design in this issue
> reaches rough consensus. Discussion of the overall shape is welcome here.

## Open questions
(Epic 本文の ## Open questions をそのまま)
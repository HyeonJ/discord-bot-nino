# Provider Neutral Failover Design

## Goal

Allow Nino to use any configured primary backend first, then automatically route to fallback backends when the primary is unavailable, quota-exhausted, cooled down, or too slow to answer.

## Design

The primary backend is not hardcoded. Operators choose it with `PRIMARY_BACKEND`, and choose the ordered fallback chain with `FALLBACK_BACKENDS`. Runtime backend status lives in JSON files under `runtime/backend-status`. The router treats backends with active `quota_exhausted`, `cooldown`, `maintenance`, or `disabled` status as not routable, regardless of provider identity.

The relay keeps request ownership. Initial routing sends to the first routable backend in `[primary, ...fallback]`. If a pending Discord request times out, the relay asks the router to route only to a later fallback backend. If a backend eventually replies after another backend already completed the request, existing request ownership prevents duplicate completion.

## Scope

This phase implements:

- provider-neutral runtime status files;
- router exclusion for quota/cooldown/maintenance/disabled states;
- manual backend status script;
- timeout fallback API and relay integration;
- documentation for Codex-primary, Claude-fallback operation.

Automatic quota text detection from tmux output can be layered on top by setting the same runtime status files.

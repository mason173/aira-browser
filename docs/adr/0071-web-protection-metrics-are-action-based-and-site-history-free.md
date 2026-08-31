---
status: accepted
---

# Web protection metrics are action-based and site-history-free

Aira measures webpage-protection activity as three exactly reconciling action categories: blocked request occurrences, cleaned navigated URLs, and newly hidden page elements. Only actions actually executed by the Rust-authority request path or its ArkWeb DOM adapters enter the current-page and user-clearable regular-profile totals. ArkWeb's independent ad filter is disabled for every attached controller, its `onAdsBlocked` observation chain is retired, and no separate engine-summary count enters the model. The displayed current-page categories therefore reconcile mechanically to the page aggregate; private activity is session-ephemeral, and Aira stores no per-site protection history or ranking. Privacy-oriented subscriptions such as EasyPrivacy are presented as effective coverage rather than an additive tracker count until every runtime path can provide reliable purpose attribution. Retired extra JSON fields are ignored while preserving the three valid action categories, filtering preferences, subscriptions, custom rules, and site exceptions.

This favors truthful, explainable, privacy-preserving metrics over unverifiable advertisement or tracker claims, historical site analytics, or a fabricated conversion of legacy totals.

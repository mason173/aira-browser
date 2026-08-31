---
status: accepted
---

# Sync Experience Is the Single State-Transition Owner

All App actions that change synchronization state pass through the existing Sync Experience module. Bookmark Sync and Personalization Sync remain independent deep Domain modules, while Provider eligibility, Automatic Sync, Additional Backup, and persistence are subordinate implementation; pages retain only input, platform interaction, and presentation wiring. This preserves the current UI and operation-specific commit semantics while rejecting peer orchestration, parallel authorities, permanent forwarding bridges, and a new top-level manager or facade.

Amended 2026-07-17: first activation selects the configured provider without pre-running either Domain, then initializes each user-selected Domain exactly once. One Domain's success remains enabled when the other fails or requires conflict resolution. A successful Bookmark conflict-resolution merge already establishes the remote state and durable baseline, so Sync Experience enables Bookmark directly instead of repeating full initialization. Established Active Provider switching retains the stricter rule from ADR-0047: every currently enabled Domain prepares against the target before the local Active Provider changes.

Established-provider preparation and the final Active Provider commit run inside the Automatic Runtime's existing serialized execution tail. An in-flight or queued old-provider automatic run therefore finishes before the switch begins, while automatic work requested during the switch runs only after the new provider has been committed. No second transition lock or queue is introduced.

The same execution tail is the barrier for every Provider identity mutation: Huawei sign-in/profile refresh/sign-out, selection-time activation, WebDAV configuration replacement and rollback, Provider/Domain enablement, Additional Backup target activation, and App Service Mode deactivation. `SyncExperienceProviderOperations` owns these complete transitions; WebDAV configuration is not a peer state-transition owner. Its candidate validation, previous-settings snapshot, target preparation, final commit, and rollback stay in one queued operation, while `SyncExperienceProviderActivation` remains a subordinate platform/auth executor.

Amended 2026-07-18: automatic Bookmark or Personalization failures update Provider runtime health/error state and remain eligible for the existing bounded retry, but never create a global foreground modal when the App resumes. The Sync surfaces remain the passive place to inspect recent Provider errors. Manual sync, Provider switching, and configuration operations continue to return their operation-local success or failure presentation. No error-string classification or network-specific popup policy is introduced.

Amended 2026-07-28: the user-authorized narrow exception for Huawei Space Personalization progress code `1` adds system-update guidance to the manual Sync result and the passive Sync attention status. The App advises updating to the latest system version, restarting, and retrying; it does not claim that every code-`1` failure is conclusively caused by an old system. This classifier applies only to the existing Huawei Space Personalization error marker, does not alter other Providers or progress codes, and does not create an automatic foreground modal, notification, or Toast. Transport, retries, runtime persistence, merge/apply, and Provider ownership are unchanged.

Amended 2026-07-18: successful automatic Bookmark Sync updates the remote-status cache and Sync refresh signal silently. It does not show a Toast, system notification, global modal, or other unsolicited success presentation. Manual Sync keeps its operation-local result presentation.

Amended 2026-07-21: remote-status reads are serialized across Sync Experience consumers so an older in-flight read cannot overwrite a newer completion result. A failed or unavailable remote summary remains an explicit unavailable/error summary in the passive Sync surface and must never be coerced into a truthful-looking `0 个文件夹，0 个书签`. Each configured provider, including Huawei Space, retains its manual provider-check action; that action reports its own read failure locally. These status/cache rules do not change snapshot authority, merge results, baselines, Provider identity, or Huawei system cloud propagation semantics.

Amended 2026-07-22: successful automatic Bookmark completion does not issue a second Provider read after the Domain has
already confirmed the complete remote snapshot and commit. The Bookmark Domain projects the passive folder/bookmark
summary from that confirmed result, and Sync configuration persists the active Bookmark runtime state plus its matching
remote-status cache in one serialized settings mutation after the separate baseline commit has completed. The Automatic Runtime publishes its normal execution-tail
refresh once; there is no peer automatic-completion reader or second refresh signal. A user-requested provider check
remains a real serialized Provider read through `SyncRemoteStatusCoordinator`, including its unavailable/error behavior.
This completion optimization changes neither the merge result nor Provider identity, baseline, CAS, conflict, retry, or
Huawei system cloud propagation semantics.

Amended 2026-07-22: Sync Experience also owns the one-time Huawei Space Bookmark protocol re-enable transition. Startup
eligibility is persisted separately from Provider configuration, but the transition itself remains serialized through
the existing Sync Experience owner: it pauses only the active Huawei Space Bookmark Domain, exposes one App-level
prompt plus a persistent `需要重新开启` Sync status, and routes the user's action into the existing Bookmark Domain
enablement path. It never signs out the Huawei identity, changes Active Provider, disables Personalization, removes
Huawei/Aira/WebDAV backup roles, or adds a parallel migration sync algorithm. `稍后处理` acknowledges only the prompt;
the required state remains until confirmed current-generation Bookmark activation succeeds. G4 advances the bounded
upgrade marker to version 4, clears only the stale Huawei Bookmark runtime/remote-status presentation, and preserves the
Personalization runtime state. A still-pending older Bookmark re-enable is carried forward into the G4 requirement rather
than being silently marked complete.

Amended 2026-07-22: the Provider-selection surface names `huawei_space` directly as `华为云空间`, rather than the
indirect label `华为设备之间`. Its help text explains the actual ownership boundary: Aira uses the user's own Huawei
Cloud Space to synchronize supported Aira data between Huawei devices, and that sync content does not pass through
Aira's cloud servers. This is a presentation clarification only; Provider identity, Domain scope, activation,
entitlement, storage representation, merge, and conflict behavior do not change.

Amended 2026-07-21: the first-activation “选择同步内容” sheet obtains its leading icon artwork from the Canonical Aira
Icon Catalog. Icon-ID and glyph changes on that sheet are presentation-only: they must not alter item identity, ordering,
default selection, toggle behavior, submit eligibility, provider selection, Domain initialization, or transition ownership.

Amended 2026-07-25: first activation or re-enablement of the Huawei Space Bookmark Domain no longer holds the Sync
Experience operation open while ArkData materializes and confirms a complete G7 snapshot. The existing transition owner
atomically persists Bookmark enabled, a non-zero durable pending marker, and an unblocked idle Huawei Bookmark runtime,
then schedules the existing Automatic Runtime and returns without a progress dialog or completion modal. The passive
Sync surface reports `初始化中` until the first real success. Process termination merely pauses execution: cold start,
foreground entry, reliable-network recovery, periodic execution, and manual `立即同步` resume or retry the same pending
work. Retryable initialization failures use bounded 10-second, 30-second, 1-minute, 2-minute, then 5-minute delays;
blocked failures stop automatic retry and remain visible as attention. The current-generation Huawei re-enable marker
cannot complete while pending, before a real success, or while blocked. This introduces no second transition owner,
queue, journal, or Bookmark algorithm, and does not change Aira Cloud, WebDAV, Personalization, Additional Backup, merge,
baseline, or G7 storage behavior.

Amended 2026-07-26: the existing Aira Cloud to Huawei Space handoff for an enabled Bookmark Domain uses the same silent
presentation as first Huawei Bookmark activation. The provider-change confirmation remains explicit, but after the user
confirms, Sync Experience does not open a long-running progress dialog or a completion modal; the persisted Provider and
Bookmark pending marker drive the passive `初始化中` state while the Automatic Runtime finishes. During that pending
window, Sync Experience and Advanced Sync status reads return a passive “后台初始化，等待云端确认” summary from the
persisted marker instead of executing a Huawei remote-status read that is intentionally unconfirmable and displaying
`远端数据读取失败`. Once pending clears, ordinary remote-status reads resume. This presentation/status correction does
not change the confirmation boundary, Provider commit, Bookmark algorithm, retry policy, Aira Cloud, WebDAV,
Personalization, Additional Backup, baseline, or G7 storage behavior.

Amended 2026-07-31: the Sync Experience remains the sole transition owner for the authorized Novel Bookshelf companion.
Its fifth device-local selection is presented by the existing Personalization surface, routed through
`SyncPersonalizationDomain`, and included in first activation, Provider switching, Additional Backup, pause/resume, and
automatic local-change execution without introducing a peer Domain owner or a fifth G2 section.

Amended 2026-08-02: first-activation WebDAV configuration preserves the current device-local content selection before
opening the configuration page, whether the user selects the WebDAV Provider row or uses its explicit edit action. After
configuration succeeds, the existing Sync Experience continuation initializes exactly those selected Domains and items.
Ordinary WebDAV configuration outside first activation keeps its Bookmark-only activation command. Selection state is
not serialized into route parameters, and this correction changes no Provider transport, snapshot, merge, baseline,
CAS/ETag, Additional Backup, or remote-storage behavior.

Amended 2026-08-04: after the first-activation selection surface closes, Huawei Space activation keeps the Sync page
mounted with an inline `正在开启华为云空间同步` status until refreshed persisted state is available. It does not replace the
existing silent Automatic Runtime handoff with a progress or success modal. If activation is blocked or fails, the page
renders a recoverable `同步尚未开启` state with a setup entry instead of an empty body. If refreshed state cannot be read,
the page preserves that uncertainty and offers a state-read retry rather than claiming Sync is inactive. This is
presentation-only and changes no Provider/Domain transition ordering, pending marker, retry, snapshot, baseline, merge,
or remote-storage behavior.

Amended 2026-08-05: reconstructing the Sync surface waits for an in-process goal-change operation to finish before it
decides that no Active Provider exists. Leaving and reopening the page during first Huawei Space activation therefore
cannot read the pre-transition `none` state and reopen first-provider selection; it resumes from the Provider, enabled
Domain, and pending marker already persisted by the existing transition. A blocked or failed activation still returns
to recoverable setup. This is an owner-level state-read barrier only, not a new transition lock, persistent journal, or
change to Provider/Domain commit ordering, Automatic Runtime, snapshot, baseline, merge, or remote storage.

Amended 2026-08-25: a manual ordinary synchronization covers already queued automatic work for the same selected
Domains. If an automatic Domain run completes successfully while the manual request waits on the shared execution tail,
the manual request adopts that result only when Provider identity and the Domain's local-change revision still match;
otherwise it runs the Domain again. Automatic intent that predates a manual Domain start is consumed, while a local
mutation after that start retains its own revision and debounce run. Only successful ordinary manual completion restarts
that Domain's periodic freshness window. Retryable failures keep their classified bounded retry delay, and blocked
failures remain stopped. Backup and Provider-maintenance operations do not claim ordinary freshness. This remains one
Automatic Runtime and one serialized execution tail rather than adding a second scheduler or cancellation authority.

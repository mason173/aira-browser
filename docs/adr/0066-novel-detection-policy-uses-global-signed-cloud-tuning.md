# Novel Detection Policy Uses Global Signed Cloud Tuning

Accepted: 2026-08-03
Status: Superseded for current clients on 2026-09-01

## Package-owned revision

The current App reads one immutable copy of `DEFAULT_NOVEL_DETECTION_POLICY` from the package. Manifest fetch, watch,
signature/schema/version/expiry handling, ETag, and recoverable cache code are deleted. Detection budget or strategy
selection changes require source review and an App release. The private server endpoint remains temporarily for older
clients and is not a dependency of the current client.

The original decision below is retained as delivery-history context; its remote lifecycle is no longer current.

## Context

Some novel sites render book and chapter content only after a hash or History API route commits. The compiled generic
DOM detector can recognize those pages once the evidence exists, but fixed retry timing and incomplete SPA route
re-entry can delay compatibility fixes until another App release.

The signed Novel Rules catalog from ADR-0057 is intentionally site-scoped. Extending it with a wildcard host or adding a
new host/path rule would make generic recognition a site allowlist and would not repair equivalent SPA sites.

## Decision

`NovelReaderApplication` and `NovelReaderController` remain the owners of Novel page detection and session entry. The
ordinary Web navigation owner publishes accepted non-initial History API/hash route changes through the existing
window-scoped `BrowserRuntimeLifecyclePort`. The Novel Application consumes only its own window's signal and asks its
bound Novel Session to run the same generic page-ready flow.

`NovelDetectionPolicyCatalog` provides a synchronous immutable current policy and hides signature verification,
schema/version/expiry/app-version/rollback validation, ETag handling, foreground watch, and a recoverable app-private
cache. Invalid, incompatible, expired, unavailable, lower-revision, or same-revision/different-content data never
replaces the packaged default or a still-valid accepted snapshot.

The server publishes a complete RS256 envelope at `GET /novel-detection-policy/v1/manifest`. Schema v1 has exactly four
global fields:

- a strictly ascending list of positive retry delays;
- a bounded maximum probe-run count per navigation, including the initial immediate run;
- a generic SPA route reprobe flag;
- a strict enum list selecting precompiled detection strategies.

The first compiled strategy is `dom_evidence_v1`. This ID names the bounded class of reviewed generic DOM evidence, not
an immutable detector binary. App releases may refine its compiled grammar only when the evidence remains generic,
preserves the established false-positive guards, and is recorded in this ADR. The policy has no host, domain, path,
selector, regular expression, JavaScript, cookie, request header, credential, page identity, forced takeover, or UI
eligibility field. The App also coalesces concurrent probes for the same navigation generation and enforces the total
probe budget across duplicate page-ready signals.

ADR-0067 separately allows the signed, host-scoped Novel Rules catalog to locate bounded DOM recognition evidence under
compiled structural gates. That does not add site fields to this global policy and does not permit either catalog to
declare eligibility directly.

The August 6, 2026 grammar revision recognizes a bounded leading Arabic or Chinese ordinal followed by common
Chinese/ASCII list punctuation and non-empty Chapter title text. Book recognition still requires Catalog density plus
existing Book or Start Reading evidence. Chapter recognition accepts that ordinal form only with a positive numeric
terminal URL identity, explicit Previous/Next Chapter navigation, and more than 400 characters of selected content;
ordinary Previous/Next Page navigation does not satisfy the new identity. The revision adds no host/path rule or remote
selector and changes no cloud schema field. Clients compiled before this revision cannot receive the new eligibility
grammar by changing or pushing the schema-v1 cloud policy.

The envelope reuses the provisioned Novel RSA key material by default but has the distinct key ID
`aira-novel-detection-policy-rsa-20260803` and type `AIRA-NOVEL-DETECTION-POLICY`, preventing substitution with Novel
Rules or Media Detection Policy envelopes. The App refreshes through the existing deferred Novel catalog warmup and
foreground/background lifecycle entry points. While foregrounded, it uses bounded long polling at
`GET /novel-detection-policy/v1/watch`; authenticated manual push only wakes watchers and cannot carry policy content.

## Operations

The authoring snapshot is `server/novel-detection-policy/manifest.json`. Publication requires a higher revision and a
fresh validity window no longer than 45 days. The server persists the highest normalized revision/content identity in
its data directory. Rollback republishes older bounded values under a higher revision.

After atomically deploying the authoring snapshot and server code, operators may use **推送小说识别策略** in `/admin`
or authenticated `POST /admin/api/novel-detection-policy/push`. Deployment and push are separate actions. Old clients
continue using the unchanged `/novel-rules` contract and do not consume this endpoint.

## Consequences

- Equivalent dynamic novel sites benefit without a domain allowlist or site-specific selector rule.
- Retry effort and SPA re-entry can be tuned without shipping executable behavior.
- Cloud data cannot make a page eligible by itself; the compiled generic DOM evidence remains authoritative.
- A new detector, evidence source, ArkWeb hook, or material eligibility rule still requires reviewed App code and a
  corresponding ADR revision. Adding or changing a remotely selectable strategy or capability also requires a cloud
  schema revision; a compiled grammar refinement that adds no remote field does not.

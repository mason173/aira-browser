# Media Detection Policy Uses Global Signed Cloud Tuning

Accepted: 2026-07-30
Status: Superseded for current clients on 2026-09-01

## Package-owned revision

The current App reads one immutable copy of `DEFAULT_MEDIA_DETECTION_POLICY` from the package. Manifest fetch, watch,
signature/schema/version/expiry handling, ETag, and recoverable cache code are deleted. Changes to probe effort or the
compiled name lists require source review and an App release. The private server endpoint remains temporarily for older
clients and is not a dependency of the current client.

The original decision below is retained as delivery-history context; its remote lifecycle is no longer current.

## Context

Video sites frequently vary iframe timing, player bootstrap order, and SPA route behavior. Shipping every generic probe
tuning change in a new App version delays compatibility repairs. A site/domain rule catalog would also turn detection
into an allowlist and leave technically similar sites behind.

The existing media pipeline already has one evidence-driven authority: discovery produces observations, Session
Resolution selects a session, and Reachability decides whether native takeover may be offered. Cloud delivery must not
become a second authority for the blue takeover button.

## Decision

All eligible pages continue to run the compiled generic detection pipeline. `MediaDetectionPolicyCatalog` is a deep
module with a synchronous current-policy interface and a non-blocking conditional refresh. It hides envelope signature,
schema/version/expiry/rollback validation, ETag handling, and the recoverable last-valid App cache.

The server publishes a complete RS256 envelope at `GET /media-detection-policy/v1/manifest`. Schema v2 has exactly nine
global fields:

- deep-probe delay list;
- maximum deep-probe runs per navigation;
- maximum concurrent deep probes;
- generic SPA-route reprobe enabled state;
- a strict enum list selecting precompiled snapshot scanner strategies;
- bounded media-field, media-query-parameter, player-method, and global-config ASCII name lists.

Every number and list has an App-enforced bound. Delay lists are strictly ascending and begin at zero. The manifest has
no host, domain, path, selector, regex, JavaScript, cookie, header, credential, media URL, active-session, Reachability,
or UI eligibility field. String lists are local matching data, not code or selectors. Remote data can tune only
strategies already compiled into the App, and the existing Evidence -> Session Resolution -> Reachability chain remains
authoritative.

The media envelope reuses the provisioned Novel RSA key material by default but uses a distinct key ID and envelope type.
This reuses the small delivery primitive without reusing Novel's site-rule model or allowing cross-schema substitution.
The App refreshes during deferred startup and on foreground. While foregrounded, it also holds one bounded 20-second
`GET /media-detection-policy/v1/watch` request; a changed revision or authenticated manual Push signal causes a fresh
signed-manifest fetch. The watch transports only revision/wake metadata and cannot carry policy. No database, remote
code, rule editor, or rollout service is added.

## Operations

The authoring snapshot is `server/media-detection-policy/manifest.json`. Publishing requires a higher `revision` and a
fresh validity window of at most 45 days. The server persists the highest revision and normalized content identity in
its data directory, rejecting rollback or same-revision/different-content publication across restarts. Rollback
republishes the previous bounded values under a higher revision.
Invalid, incompatible, expired, unavailable, bad-signature, lower-revision, or same-revision/different-content data is
ignored; the last currently valid signed snapshot or packaged default remains active.

After the snapshot is atomically deployed, operators can use **推送视频识别策略** in `/admin` or authenticated
`POST /admin/api/media-detection-policy/push`. This wakes only connected foreground watch requests; publishing and
validation remain separate operations.

## Consequences

- A generic compatibility tuning can ship without an App release or domain allowlist update.
- Similar sites benefit from the same evidence-gathering improvement automatically.
- The cloud policy cannot force a takeover session or button and cannot introduce executable behavior.
- Newly observed player field, query parameter, method, or config names and combinations of existing scanner strategies
  can be shipped without an App release.
- A genuinely new detector, iframe capability, evidence source, runtime hook, or ArkWeb behavior still requires reviewed
  App code and a schema/ADR revision.

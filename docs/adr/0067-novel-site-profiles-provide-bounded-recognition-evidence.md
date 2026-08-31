# Novel Site Profiles Provide Bounded Recognition Evidence

Accepted: 2026-08-06

## Context

The generic Novel detector should continue to recognize common cross-site structures, but expanding it for every
single-site DOM convention increases false-positive risk. ADR-0057 already gives Aira a signed declarative Novel Rules
catalog with bounded host/path scopes and reviewed CSS selectors. Before this decision those selectors primarily served
extraction, even though detection already consumed some extraction results indirectly.

Adding a second site-recognition catalog would duplicate signature, cache, precedence, and matching behavior and split
one Novel flow across peer owners. Adding remote JavaScript, regular expressions, or a direct eligibility flag would
give configuration the authority of executable product code.

## Decision

`NovelExtractionService` remains the single narrative owner of Novel page recognition and extraction. Its subordinate
`NovelRuleCatalog` supplies one resolved site Profile for both operations. `NovelDetectionPolicyCatalog` remains
separate and global: it controls only retry timing, probe budgets, SPA re-entry, and selection among compiled generic
strategies.

The existing Novel Rules schema-v1 selectors may contribute bounded recognition evidence without a schema revision:

- a Book Profile must select at least three unique non-empty same-origin HTTP(S) links inside its declared path scope,
  and the page must still expose a non-empty title plus compiled Book structure or a reading action with Catalog evidence;
- a Chapter Profile must select a non-empty title and more than 400 characters of accepted content, and it must expose a
  valid same-origin Previous/Next Chapter relationship inside its declared path scope;
- remote content selectors retain ADR-0057's stricter quality gate;
- a Profile never returns eligibility directly. If Profile evidence fails, the existing generic detector remains the
  fallback; an explicit signed or packaged block rule remains the only configuration that suppresses eligibility.

Remote data still cannot contain JavaScript, arbitrary regular expressions, request headers, cookies, credentials,
cross-origin acquisition instructions, or new transport/decoding algorithms. Complex acquisition remains a compiled
Recipe that a remote rule may inherit only under ADR-0057's exact ID and scope rules.

Generic recognition expands only for a demonstrated cross-site semantic pattern with independent structural guards and
negative controls. A single site's selectors, markup names, path layout, timing, or DOM quirks default to a site Profile.
Repeated Profiles that reveal the same host-independent pattern may later justify a reviewed generic refinement.

## Consequences

- Future single-site compatibility fixes ship through reviewed packaged Novel Rules in an App release.
- Existing clients continue to parse the unchanged schema. They receive selector/extraction improvements they already
  understand; the stronger Profile recognition semantics begin with the App version containing this decision.
- Generic unknown-site coverage remains available and conservative.
- Site logic does not enter `BrowserShellPage.ets`, UI components, or parallel detection engines.
- A bad or stale Profile falls back to generic recognition/extraction and cannot force arbitrary pages into Novel Mode.

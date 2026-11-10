# Aira shared membership page

Official uses `KitappMembershipPage` from `kitapp-membership` for the Aira and app-suite tabs. Community keeps its existing local-only introduction and never exposes Huawei purchasing. The source default remains Community. Both distributions require HarmonyOS API 26 or newer (`compatibleSdkVersion` and `targetSdkVersion` are `26.0.0`); API 23/24 devices are outside the supported range.

The fixed modules are JuDesign 1.35.13 and KitappMembership 1.3.17, published in `mason173/JuDesign` (`832fb23`; page support in `0d91831` and `85c4560`). They were imported with the upstream vendor scripts. `AiraBrowser/judesign.lock.json` and `kitapp-membership.lock.json` protect every source and asset. Do not modify these copies; update upstream, publish a new version, then vendor it.

`AiraProMembershipCatalog` adapts the existing overview view model into the single-app offer. It retains the Huawei lifetime price, existing benefit owner, permanent/timed membership policy, monthly and annual plans, subscription management, code redemption and complimentary claim. These auxiliary actions use the product component's `appActions` interface and appear only on the Aira tab. The suite catalog and layout remain owned by the fixed module.

The existing purchase coordinator still owns login, privacy boundaries, Huawei purchase, server verification and delivery confirmation. It now requests explicit purchase consent before starting payment for every entry point, including feature-unlock, renewal and campaign actions. Each dialog starts unchecked and links to Aira's actual membership and privacy documents; monthly and yearly plans additionally require the auto-renewal agreement. Opening a document first dismisses the confirmation and never initiates payment. Cancellation, page disposal, privacy-boundary changes and account-session changes (including A→B→A) reject the pending purchase. Restore does not request new-purchase consent. The page shares one busy flag between purchase and restore, refreshes observable offer state after completion, and pauses the component when inactive or covered by a sheet. Component activation is reported through the API 26 `ComponentActive` and `ComponentInactive` lifecycle decorators; a nested component does not rely on router page-only callbacks.

The suite tab now sells the separate nonconsumable `aira_suite_lifetime` SKU in Aira, using `suitePurchaseEnabled: true` and server-owned `suiteOwned`. Its buy and restore callbacks use `suite_lifetime` through the existing purchase coordinator; it no longer opens the Kitapp store. The earlier Aira lifetime-purchase entitlement rule is unchanged.

Suite checkout links the authenticated Aira account to its cross-app identity before forcing an authoritative suite-ownership refresh. This ordering prevents a newly linked owner from buying the same suite again. An unconfirmed server response cannot permit checkout. The shared confirmation uses `suite: true`, preserving its fixed name, icon and price. After account linking and after each native environment/product query, the account and page/confirmation generation must still be current before launching payment. Once the cashier opens, verification uses the exact account session rather than page activity, because the system cashier itself can make the page inactive.

The existing authenticated receipt transport verifies the new SKU server-side, records the suite independently, and only then confirms delivery. Modern `jwsPurchaseOrder` fields are decoded for delivery confirmation; this client decoding never substitutes for server signature verification. Suite-only recovery queries current and unfinished nonconsumables, deduplicates matching receipts, and refreshes server rights even if the native list is empty. A best-effort account re-link failure cannot block a previously linked server entitlement. Suite state is received with the authoritative account response, isolated to the current session, cleared on account changes, and forwarded reactively to the shared page. It is not a locally issued Pro grant.

The Official membership surface uses Aira's existing `SettingsHdsScaffold` only as the measured top-safe-inset owner (`showTitleBar: false`, `useTopSafeInset: true`, `contentKind: 'unframed'`). The shared page uses `asDestination: true`; its destination inherits the top inset and owns the single “会员” navigation title. The scaffold creates no second title or HDS navigation shell. The missing inset was reproduced by an emitted-host regression before the fix, then passed after rebuilding. No arbitrary top spacer or shared safe-area behavior was introduced.

Aira continues to own the application's appearance and color mode. This integration does not call the library's appearance initializer or replace Aira's theme persistence. Only the membership surface uses the library's existing resource tokens.

Both DevEco and command-line builds run `scripts/check-aira-shared-components.cjs`. Private signing profiles may predate the additional HAR modules, so the build script adds missing repository-declared modules to its temporary effective profile while retaining private signing/products; the tracked template is restored on exit.

Validation:

- `node scripts/check-aira-api-baseline.cjs`
- `node scripts/check-aira-shared-components.cjs`
- `node scripts/check-aira-shared-membership.cjs`
- `node scripts/check-aira-purchase-consent.cjs`
- `node scripts/check-aira-suite-iap.cjs`
- `node scripts/check-aira-shared-membership-native.cjs` (after the native build)
- `./scripts/check-aira-pro-renewal-contract.sh`
- `AIRA_DISTRIBUTION=official SKIP_INSTALL=1 ./scripts/build-aira-browser.sh`
- `AIRA_DISTRIBUTION=community AIRA_ALLOW_UNSIGNED_BUILD=1 SKIP_INSTALL=1 ./scripts/build-aira-browser.sh`

Build and JavaScript replay checks do not constitute device visual, gesture or real-payment acceptance. No device screen capture or UI automation is used.

Huawei references: [component lifecycle](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-custom-components-new-lifecycle/), [AppGallery listing links](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/appgallery-kit-faq-0002/), [native dialog API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-uicontext-promptaction/).

Verified on 2026-11-06: both Official signed and Community unsigned builds passed; the four existing-policy-to-shared-offer regressions, renewal contract, fixed-source checks, emitted host callback/flight replay and upstream emitted product tests passed. The final Community build used `SKIP_INSTALL=1`. The final Official signed build used `SKIP_INSTALL=0` and installed successfully to the one connected HDC device. No device UI was operated. The five new purchase-consent/session regressions also passed. The source Community identity and placeholder endpoint were restored after each build.


The 1.3.17 confirmation refinement groups the application icon, product and price into one neutral summary, keeps billing notes outside that summary, flows agreement links within the checkbox paragraph, and places Cancel and Confirm Purchase side by side. Aira passes its existing application icon; subscription prices use the existing amount and cadence fields while renewal information remains visible in the billing note and agreement. No purchase authorization or recovery semantics changed.


Suite integration follow-up, 2026-11-06: the existing shared modules remain JuDesign 1.35.13 / KitappMembership 1.3.17; no pinned copies were edited. The old store-only entry was reproduced by a failing emitted-host check before the change. All 19 purchase-consent/suite regressions, existing offer-policy and renewal contracts, fixed-source checks and final emitted-host purchase/restore/ownership checks passed. Community unsigned and Official signed builds passed and restored Community source defaults. The final build found no HDC targets, so this suite-integration package has not yet been installed. No purchase was initiated and no device UI was operated. Backend verification/deployment records are kept in the private backend repository.


Suite confirmation links its membership clause to the existing Kitapp One membership agreement through `suite_membership_service_agreement`; Aira Pro plans retain the Aira Pro agreement. The suite agreement URL returned HTTP 200 and its link-selection regression passed. This registers a document link, without editing or publishing legal text.

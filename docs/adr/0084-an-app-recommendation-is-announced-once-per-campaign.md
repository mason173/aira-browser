---
status: superseded
supersedes: none
---

# An App Recommendation Is Announced Once Per Campaign

Superseded by ADR 0089: the card and its content catalog moved to 设置 → 应用推荐, opened on demand, and its
per-campaign memory, homepage trigger, and reserved surface are gone. Its store hand-over and bundled icon rule
survive in ADR-0086 and `BundledShortcutIconResources`.

Accepted 2026-10-19. Aira tells the user once, on the phone homepage, about a companion app worth installing. The
announcement is an introduction: it names the app, says what it is for, shows sample reviews and answers, and offers one
action that hands the app's AppGallery detail page to the store. Aira itself installs nothing and never reads whether
that app is already installed.

"Once" means once per recommendation, not once per install. Aira will recommend more than one app over its life, and a
user who closed the first card has not agreed to hear about every app Aira ever ships — but has also not agreed to hear
the same thing twice.

## Decision

Each recommendation is a named **campaign**, and the device-local memory is keyed by campaign.

- `AppRecommendationRecord` holds `id`, `shownAt`, and `dismissedAt`, and the whole store is one list of those records
  in the preferences store `aira_app_recommendation`. "Shown once, or closed once, is the end of it" now ends only that
  campaign.
- The record deliberately does not model the recommended app — no bundle name, no store URL, no install flag — because
  those belong to the AppGallery and to the Marketing API. "Is it already installed?" is not a question Aira can answer
  honestly, and pretending to answer it would mean reading the user's installed-app list for no reason. The campaign id
  is a presentation identity, and that is the only thing this store knows.
- `id` is the campaign identity, not the app identity, and it is stable for as long as the same telling should stay
  spent. Recommending the same app again later is a new push and takes a new id (`shengxi`, then `shengxi_2027`), because
  a user who closed the previous card did not refuse the app forever. Changing the id is the only way to re-announce a
  campaign; nothing else in the tree can bring a spent one back.
- The memory is device-local rather than account-bound. A fresh install starts from an empty store, so someone who
  uninstalls Aira and installs it again is told once more; a user who keeps Aira is never told twice about the same
  campaign. Nothing is derived from the app version, so an update never re-announces a spent campaign either.
- `AppRecommendationCoordinator` owns eligibility and presentation, and it owns no content. The ordered campaign list
  arrives through the shell facts, and the coordinator offers the first campaign this device has not spent. It presents
  a full-height phone sheet through the shared transient surface id `app_recommendation`, exactly like the toolbar
  lesson and the welcome-gift notice.
- At most one card is offered per homepage arrival. The lane that automatic prompts share can be held by a release
  notice, the welcome-gift notice, or the toolbar lesson, and a prompt holding the lane defers the card rather than
  dropping it; the card is re-decided whenever that lane clears. Deferring does not re-arm, so two pending campaigns
  can never land back to back: the next one waits for the user to arrive at the homepage again.
- The campaign is spent at reveal, not at decision. A custom bottom surface mounts asynchronously, so a presentation
  abandoned before its reveal must not consume the telling. Losing the notice costs only the notice.
- The card carries exactly two outcomes: the footer action hands the campaign's AppGallery detail page to the store, and
the header's close control ends the telling without doing anything else. A tap on the scrim does nothing, because a
campaign can only be offered once and an accidental tap must not be what spends it. Back behaves like close.
- The action is a hand-over, not an install. Aira builds the store page from the campaign's AppGallery id, asks the
store's own `store://appgallery.huawei.com/app/detail` deep link to answer it, and falls back to the `https://` detail
page when the store cannot. It never launches the app, never checks whether it is installed, and never claims a reward
for installing: the store owns all of that, and a second install flow inside Aira could only fail silently in exchange
for no additional capability.
- Acting on the card spends the campaign exactly like closing it does, and the campaign was already spent at reveal, so
tapping the action cannot make the same card come back.

## How Aira Recommends A Different App

Adding a recommendation is a source change in one file plus its artwork and copy. Nothing about the memory, the
coordinator, the trigger, the surface lane, or the back handling changes.

1. Add an entry to `appRecommendationCatalog()` in
   `AiraBrowser/entry/src/main/ets/app/components/onboarding/AppRecommendationContent.ets`, with a new campaign `id`, the
   `storeId` of its AppGallery page, the app icon, and the copy resources. Deploying it alone **queues** it behind the
   current campaign: a user who never saw the current one is offered that first, on separate homepage arrivals.
2. To make the new app the next thing everyone sees, put it first in the catalog (or replace the older entry). Every
   device that has not spent the new campaign becomes eligible on its next homepage arrival, with no reinstall and no
   version gate.
3. Bundled artwork and copy live with the app, so the new campaign ships in the same four locales as everything else
   and needs no network read to draw. The review band, the laurel phrase, and the questions are optional per entry, so
   a campaign with less to say simply draws a shorter card instead of an empty one.

Because the id is the whole identity, the guard rails are simple: never reuse an id for a different app, and never
re-declare a spent id expecting it to show again. The contract check pins the per-campaign record, the catalog as the
single content source, and the fact that the card and the coordinator own no copy.

The card itself is a copy of the recommended app's own product page, so the recommendation and the app it points at
read as one product family: the app icon in a rounded square, the product name and phrase, a two-laurel product phrase,
a constantly scrolling band of sample reviews, and centred questions. The measurements are that page's.

The recommendation is phone-only, and phone-only means the shell. The large-screen and desktop information architecture
opens into its own surfaces and has no homepage of this kind, so the coordinator refuses `shellFamily !== 'phone'`
outright.

## Alternatives Considered

- One spent flag per install. Rejected: it makes the first recommendation the last one Aira can ever make, and a later
  app would need an app version bump or a reinstall to be announced.
- One spent flag per recommended app, keyed by bundle name. Rejected: it makes "we want to tell you about this app
  again, differently" impossible, and it invites the store-facing identity into a presentation record.
- A hosted campaign descriptor so the recommendation can change without a release. Rejected: it would make the
  announcement depend on a network read, on a hosted endpoint the Community distribution must not call, and on a
  server-side record of whether the user has been told. Bundled content plus a device-local memory keeps Community
  usable with no Aira production credentials.
- Gate the announcement on time, on launch count, or on the app version. Rejected: all three re-announce a spent
  campaign, which is exactly what a per-campaign record exists to prevent.
- Present every pending campaign in one arrival. Rejected: two cards back to back read as nagging, and the second one
  would arrive without the user having chosen to look at the homepage.
- Offer `查看` next to `不再提醒`, both at the bottom. Rejected for the pair: a campaign can only be offered once, so
two bottom buttons left the dismissal ambiguous, and an outside tap could not safely mean "I read this". The action
stayed, but as the single footer button, with the header's close control as the way to say no.
- Make the action install the app, or check whether it is already installed and skip the campaign. Rejected: the store
owns installation, and reading the installed-app list to decide what to show would make Aira's announcement a
different product from the one the campaign describes.

## Consequences

- The card is a full-height immersive phone sheet on the shared theme tokens. Its body is the recommended app's own
product page; its footer is one primary action that hands the store page over, and the header's close control and the
system Back gesture end the telling without acting. Either outcome records that campaign as spent.
- The sample review band scrolls at a constant speed, repeats its full cycle so the row never shows a gap, pauses while
  it is touched or off screen, and disposes its animator on unmount. Its sample reviews are labelled as samples in the
  section heading.
- The store grows by one small record per campaign and needs no migration when a campaign is added or retired. A
  campaign id that leaves the catalog keeps its record; retiring the catalog entry is enough, and the record costs
  nothing.
- Because the announcement is device-local and presentation-only, it survives provider switches, account changes, and
  Private Browsing Sessions untouched. A Private Browsing Session is refused at presentation, and the arrival that
  would have offered the card is not spent.
- The bundled laurel branches are decorative artwork whose geometry belongs to the card, so they are declared in
  `resources/icon-sources/aira/image-assets.json` as a packaged SVG exception rather than as a colorable Operational
  Icon.

## Verification

Proportional evidence is a Community build plus `scripts/check-aira-app-recommendation-contract.sh`, which pins the
per-campaign record, the single content catalog, the single presentation owner, the fixed transient surface, the
homepage-only and phone-only gates, the reveal-time spend, the one-card-per-arrival rule, the lane-blocking rule, the
store hand-over through the store service, the shell registration, the classified laurel artwork, and the absence of
recommendation copy in the card, the shell, and the coordinator. Behaviour is pinned by
`AiraBrowser/entry/src/test/AppRecommendationCoordinator.test.ets`, including the two cases this ADR exists for: a
second campaign is offered after the first was closed, without a reinstall, and the store action hands that campaign's
page over and ends that campaign.

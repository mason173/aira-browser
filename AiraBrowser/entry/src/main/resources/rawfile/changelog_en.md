# Changelog

## 3.7.1 (1000508)

2026-10-09

This release fixes ad blocking repeatedly showing a download confirmation, and adjusts history, search back, and pull to refresh.

- Blocking in-page ads with content filtering on no longer opens download confirmations over and over.
- History is kept by count only, and is no longer deleted just because it is old.
- Going back from the search page hides the keyboard first, then leaves search.
- Pull to refresh is no longer cancelled early by the gesture.

## 3.6.4 (1000505)

2026-10-07

This release fixes downloading a PDF doing nothing when tapped.

- Tapping to download a PDF in the built-in browser now shows the download confirmation and starts the download.

## 3.6.4 (1000502)

2026-10-07

This release fixes tabs being wiped without reason and ad blocking popping download prompts, and lets membership be shared across sister apps.

- Tabs no longer disappear when the app is exited right after a tab is opened, especially installed web apps.
- Blocking an in-page ad no longer triggers a download confirmation.
- Signing in links the account automatically so membership can be shared across sister apps.

## 3.6.3 (1000499)

2026-10-06

This release fixes two issues with the account capsule and download settings.

- A long nickname no longer pushes the membership badge out of the account capsule; the name truncates instead.
- Opening download settings on the PC build no longer crashes.

## 3.6.3 (1000496)

2026-10-06

This release adds a Search dock toolbar style with its matching home page, and makes search suggestions and history more useful.

- A new Search dock toolbar style puts the search box above the bottom navigation buttons, and those buttons can be customized.
- Home settings gains a Search dock home page that pairs with that toolbar style.
- Search suggestions now grow upward from the input and show up to eight.
- Search history shows recently visited pages as well as searched terms.
- In the split and search-dock bars, every button except Tabs can now have its tap customized.

## 3.6.2 (1000493)

2026-10-05

This release fixes the freeze while a page is checked for video, and lets userscript dependencies install.

- Search pages and similar pages no longer freeze for a few seconds while video is detected.
- Installing a userscript now also stores its plain JavaScript dependency libraries instead of rejecting them for a missing userscript header.
- Video detection uses less power and reports its result sooner.

## 3.6.1 (1000491)

2026-10-04

This release remembers zoom for each site, lets you arrange the toolbar, and separates the computer-link switches.

- Each site remembers its text size and page zoom.
- Bottom-bar tools can be arranged from the add sheet, and the current address appears in the toolbar.
- The page pauses while Huawei payment is opening, so it is harder to tap the wrong thing.
- Membership cannot be purchased while signed out.
- Tabs remain after the system closes the app.
- Tabs, bookmarks, and history can be switched separately when linking with a computer. The scrolling computer-icon hint moves to the top.
- Private deployment can connect every device with the same pairing code.

## 3.5.4 (1000485)

2026-10-01

This release adds a language choice and webpage translation, and adjusts the home toolbar, tab titles, and tab cards.

- Settings can follow the system, or use Simplified Chinese, Traditional Chinese, or English.
- The toolbar can translate the current page. Scrolling stays smooth while translation is on.
- Phones can zoom the current page.
- Toolbar gestures are explained one step at a time.
- On the classic home with a photo or video wallpaper, the split top and bottom bars turn clear and the icons follow the wallpaper.
- Site slogans no longer trail the tab title. Zhihu shows “知乎”; an article still shows its own title.
- Tiled tab cards frame the middle of the page and leave out the address bar. Leaving the page keeps that picture on the card.
- The computer-link page and its tutorial are easier to follow. The phone shows the desktop browser’s own name and icon.
- After a portrait video, the screen returns to the previous landscape orientation.
- With the in-app proxy on, file downloads use that proxy too.

## 3.5.3 (1000480)

2026-09-30

This release runs a National Day offer for long-term members and fixes a few issues in the launch screen, the membership page, and the tab list.

- From October 1 to October 7, the long-term membership costs ¥48, marked 30% off. The regular price returns after the offer ends.
- The membership page no longer lists the phone client separately.
- After changing the app icon, the launch screen no longer keeps showing the old icon.
- Opening the tab list no longer squashes the page.
- Automatic and solid-color wallpapers now sync correctly.
- Returning from the background resumes the home video wallpaper.

## 3.5.2 (1000479)

2026-09-29

This release adds video wallpapers and more logos to the home page, adds a list style to tabs, and fixes a few issues in the address bar, bookmarks, and membership.

- The home page can play a muted, looping video wallpaper. Coming back from another page no longer flashes the video.
- Home logos gain Pixel, Edge, Round Brush, Signature, and Ribbon, with an opacity control. Setting full transparency no longer makes the search box jump.
- The tab overview gains a list style, with recently used tabs at the bottom. Closing the overview from a page no longer flashes the home page first.
- The top address bar follows the current page. In the split layout, the address bar sticks to the top of the page.
- The bookmarks bar and "Other bookmarks" can be switched by swiping. Tapping a history section header switches sections.
- When a membership expires you can choose the long-term plan. A gifted membership can still be purchased.
- Removing a web app from the desktop also removes its install record in settings.
- At smaller display sizes, tab cards still fit on screen. Tapping a tab on another device opens that site.

## 3.5.1 (1000476)

2026-09-29

This release adds logo and wallpaper appearance settings to the home page, and fixes a few issues in search, tabs, and the toolbar.

- Home settings gain "Logo": the Simple and Minimal home icons can use a preset style or your own image, and the size is adjustable.
- The home wallpaper settings are refreshed, with more consistent colors and mask layers.
- Typing in the address bar suggests history and bookmarks.
- In the split layout, the address bar and bottom bar are sized more accurately, so pages are neither covered nor left with a blank strip.
- Searching from the middle of the Simple or Minimal home page no longer flashes a white page first.
- Closing the current tab returns to the previous tab instead of jumping to the end of the list.
- On phones, Simple home shortcuts lay out left to right instead of being pushed to the middle.
- The "swipe up the middle capsule" option shows the current selection instead of staying on the previous one.
- Installing a .user.js script from a file supports more sources and navigation forms.

## 3.4.3 (1000472)

2026-09-28

This release merges the split-layout search into the same logic as the floating search, and fixes a few issues in history, the bottom toolbar, and membership.

- The split-layout search and the floating search become one: shortcuts, Esc, back, and cancel behave the same, and searching again right after closing is neither interrupted nor crashed.
- History page: "Edit" is no longer greyed out when the site list has content, and switching between "Timeline" and "Sites" no longer gets stuck loading.
- After reordering bottom toolbar icons by long press, the other icons still respond to taps.
- On desktop, "Show bookmarks bar" becomes a three-way choice: always, only on new tabs, and never, matching the bookmarks bar's own menu.
- The membership page accepts a redemption code directly; a confirmed membership is no longer cleared by a later refresh; the retired quarterly plan is no longer requested.
- The size limit for installing a .user.js script from a file rises to 50 MB, and in-page back history survives a page reload.

## 3.4.2 (1000468)

2026-09-27

This release gathers the desktop home page and home settings into a desktop layout, and makes the membership description clearer.

- The Simple home page on desktop can search in place, no longer shifts when collapsed, and lays shortcuts out from the middle outwards.
- The home settings preview becomes a desktop home page; tapping the cards on either side scrolls them to the middle.
- Home settings and "Add to home" size to their content instead of leaving large blank areas.
- The desktop tab strip opens a menu on long press.
- After a membership has been claimed, buying the long-term plan no longer asks you to wait; one-time plans are consistently called "long-term membership".

## 3.4.2 (1000466)

2026-09-27

This release rebuilds the new-user onboarding flow, moves sync into the background, and makes the home style follow the account.

- First launch guides you in order: feature intro, default search engine, home style, appearance, and finally the account and what to sync.
- Quitting before finishing the onboarding on a fresh install restarts it from the beginning next time; skipping a single page does not reset it.
- After choosing a sync method you no longer wait on a progress bar: bookmarks, home favorites and common settings, and history sync in the background and continue after leaving the page, losing the network, or reopening the app.
- The home style (Classic / Centered) now syncs with the account and stays consistent after signing in on another device.
- The Centered home page no longer shows the bottom swipe-up hint that belongs only to the Classic home page.
- Fixed appearance details in some dialogs and notice bars.

## 3.4.1 (1000465)

2026-09-25

This release keeps polishing the desktop interface and tidies up some phone details.

- Desktop tabs no longer collapse to a single ellipsis when narrow; the title keeps as many readable characters as the available space allows and hides only when it truly does not fit.
- The desktop tab style panel no longer flashes when closed.
- The desktop top notice uses card width instead of covering the whole blank row.
- On desktop, tapping the page on native pages such as bookmarks, history, and settings dismisses the address bar suggestion panel.
- The desktop toolbar gains a translate-page button and a page control button to the left of the address bar; the search engine button shows only on the home page and while editing the address.
- The Laboratory "web bottom bar avoidance" switch shows only in the phone interface; it no longer appears on desktop, and an already enabled setting is not lost.
- The Community edition adds a Telegram group to "About Aira", opening in the browser; when Aira is the default browser it opens in a new tab.

## 3.4.0 (1000462)

2026-09-25

This release gathers desktop element inspection, the bookmarks bar, and common dialogs into one desktop interface, and fixes blank new windows and Weibo video takeover.

- Desktop element inspection moves to the right side of the page, with structure, styles, console, source, and network; hovering selects an element, and the panel stays in place after a reload.
- The inspection menu uses a solid in-window background and no longer draws outside the screen.
- Bookmarks, history, downloads, offline pages, and the bookshelf share one sidebar and top bar on desktop; offline pages open as a normal tab.
- Hovering the top-right menu expands history and bookmarks and shows shortcuts on the right.
- The bookmarks bar supports right-click and long press for the same menu; folders expand level by level, and URL rows use a globe icon.
- The address bar accepts up and down keys to pick a suggestion, and Enter opens the selected one.
- Resource sniffing, the in-app proxy, script details, and "edit or paste source" become centered dialogs on desktop; the phone keeps the bottom panel.
- Web zoom starts at 100% of the page's zoom when it was opened.
- The top notice uses card width instead of covering the whole blank row.
- Car windows avoid the status bar and the bottom system buttons.
- Opening a page in a new window on desktop no longer pops up a borderless blank window.
- Weibo video takeover no longer leaves only audio with a frozen picture.
- Opening a .user.js file from an app such as WeChat enters the install confirmation instead of opening the path as a URL.

## 3.3.2 (1000455)

2026-09-23

This release adds a custom download location, turns desktop download settings into a centered dialog, reorganizes the Aira Pro page, and fixes lost sign-in state, misplaced tab previews, and third-party home page cold starts.

- Download settings become a centered dialog on desktop with a title bar, and sub-pages can navigate back inside the dialog.
- The download location can be set to a folder of your choice, and later ordinary downloads save there; private downloads still follow the private settings.
- The download confirmation uses the existing file-type icons and lets you change the save location before confirming.
- The desktop toolbar menu is reorganized: history, bookmarks, downloads, page tools, and settings open from one place.
- Settings list icons get a colored background, consistent with the existing icon resources.
- The Aira Pro page becomes a capability list plus two price cards; eligible accounts can claim 15 days of Aira Pro on the membership page.
- Centered dialogs use an opaque themed surface, so scrolled content no longer shows the page behind it.
- Cookies are saved immediately before going to the background or swiping the app away, so a site you just signed in to does not lose its session.
- Fixed the tab preview being replaced with the top of the page after a tab is collapsed or sent to the background.
- Fixed a third-party home page flashing white on a cold start, showing light colors first, and covering the page when pulling up the search.

## 3.3.1 (1000448)

2026-09-21

This release makes the tab style a three-way choice, fixes downloads and in-page navigation disturbing tab state, and adds color app icons.

- "Tab style" in Appearance now offers three layouts: tiled cards, large horizontal cards, and stacked, defaulting to tiled cards and switchable at any time.
- Fixed the current card disappearing and reappearing when entering the tab overview in the large horizontal card layout.
- Fixed the middle bar occasionally flashing the tools panel and then dismissing it on swipe up; swipe up and the "Tabs" button now share one decision.
- Fixed a bypass download such as an ad sending the page you are reading back to an old URL and reloading it, and the same download no longer notifies twice.
- Fixed reopening that tab after an in-page navigation (anchor, History API, single-page app route) returning to the old page.
- Fixed the quick search row disappearing after editing the query in a search results page's own search box, leaving back as the only way out.
- Fixed URLs opened from bookmarks, history, offline pages, or a userscript install being reopened repeatedly after the app returns to the foreground.
- Appearance → App icon gains a color icon and a tablet color icon, switchable once approved.
- The toolbar preview on the "Toolbar customization" page is now drawn statically, so entering the page no longer stutters.

## 3.3.1 (1000445)

2026-09-21

This release rebuilds the tab overview as drag-open stacked cards and wires the bottom bar, middle bar, and address bar to matching gestures.

- The tab overview becomes stacked cards and is now the default shape; cards scale by layer, so the front-to-back order is clear at a glance.
- Dragging up from the bottom bar opens the tab overview; swiping up the middle bar does the same.
- Swiping the bottom address bar left or right switches tabs.
- Closing a stacked tab uses a real fill plus throw animation, with no layer flicker while cards deform.
- After closing one tab the whole stack can still be panned and does not get stuck.
- "Toolbar customization" chooses which panel the middle bar swipe opens: the tools panel or the tab manager.
- The sync result dialog lists name and status, and long names are no longer squeezed.
- Fixed the title not redrawing after switching segmented tabs.

## 3.2.3 (1000439)

2026-09-19

This release moves the heavy part of history sync to the background and reduces sync traffic, fixes WebDAV first sync failing on some NAS devices, makes cross-device link smoother on desktop, and unifies dialogs and naming.

- History sync reads local data and computes differences in the background, so the interface keeps up during sync; an unchanged sync is skipped, and deleting a few records no longer re-uploads the whole shard.
- Compatible with NAS devices such as fnOS that create a 0-byte file when locking: WebDAV first sync no longer fails, and previously left empty snapshot files are repaired automatically.
- Cross-device link adapts to desktop: it becomes an embedded settings panel, and "link guide" opens in place instead of as a full page.
- The desktop address bar gains a "cross-device tabs" entry, showing and opening pages being browsed on other computers.
- Fixed tapping "cross-device link" on the "Sync" page on desktop being switched back to "General".
- The Chrome, Edge, and Firefox icons in the link guide become the official ones.
- Naming is unified as "cross-device link / cross-device tabs / Aira-sync extension / private deployment / page push".
- Dialog buttons are unified to a vertical layout with the primary action on top; "Clear browsing data" becomes an immersive bottom panel on phones; desktop dialogs are no longer clipped by width limits.
- Aira Pro plan prices no longer wrap onto a second line.
- The bottom toolbar gesture guide prompts once per device instead of repeatedly.

## 3.2.2 (1000436)

2026-09-19

This release gifts one month of Aira Pro to new users, supports renewing right in the app, and brings the scrolling immersion effect and bottom toolbar touch fixes.

- A newly registered account automatically gets one month of Aira Pro, with a one-time notice.
- When Aira Pro expires the app prompts you, and you can renew right in the panel and get your benefits back immediately.
- Scrolling a page down fades the top toolbar and adds a progressive blur for more immersive reading.
- Fixed the blank areas beside the capsule swallowing taps after the bottom toolbar collapses; it no longer hugs the bottom edge when collapsed either.
- Fixed a closed toolbar panel popping back up while the page scrolls.
- Fixed the home cover being stretched or jumping on a cold start, and a theme color flash when the home snapshot is handed over.
- Sync method names are unified as "Aira Cloud sync / WebDAV sync / private deployment".

## 3.2.1 (1000433)

2026-09-17

This release adds batch selection to the download list, moves the heavy part of sync to the background, and fixes userscript import, the search engine menu, and swipe-to-close tabs.

- The download list supports batch selection, managing several downloads at once.
- Importing a local userscript overwrites an installed script of the same name instead of leaving a duplicate entry.
- Secure DNS gains a strict mode switch, so an unavailable DoH no longer falls back to plaintext resolution.
- Fixed the app proxy quick switch bouncing and the search engine menu being pushed below the keyboard.
- The swipe-to-close threshold for tabs is now computed from the card width, making it easier to swipe away.
- Huawei Cloud Space and WebDAV sync reduce repeated remote reads, bookmark write projection is computed in the background, and very large history records no longer abort on a size probe failure.
- Reading overhead for the home shortcut grid and the history list is reduced, cutting main-thread jank from heavy pages and automatic sync.

## 3.1.2 (1000426)

2026-09-15

This release moves bookmark sync recomputation to the background and fixes large screens, novel reading, and first-sync deletion.

- Bookmark snapshot building and merging move to the background, so a large bookmark tree no longer blocks the interface.
- Fixed the pocket foldable staying on the touch shell after unfolding.
- Fixed novel chapters rendering with a substituted font.
- Fixed unmatched tombstones not being treated as deletions when first joining Aira-sync.
- Large-screen search suggestions gain history titles and source icons, and fullscreen, dialog width, and font scaling are corrected.

## 3.1.1 (1000420)

2026-09-14

This release spreads the light-sensing material to more surfaces, speeds up third-party home page cold starts, and tightens the bottom toolbar and tab overview.

- Manager pages, settings, history, bookmarks, the tab overview, the video assistant, and novel reading share one immersive light-sensing material.
- A third-party custom home page shows its last frame on a cold start and hands over once the page really paints, avoiding a blank base.
- The bottom toolbar and tab overview settle at 44vp, with better-aligned icons and buttons.
- Private mode runs userscripts by default, switchable in settings.
- Fixed tab cards jittering when the overview is reopened, large-screen search suggestions looking blurry, and the web video button being hard to read in light mode.

## 3.0.3 (1000416)

2026-09-13

This release greatly speeds up bookmark sync and fixes app handoff, the video assistant, and dark mode colors.

- Bookmark sync keeps deletion records for 7 days instead of 90, Huawei Cloud Space cleanup follows the same rhythm, and sync is noticeably faster once an account accumulates many deletions.
- Fixed bookmarks doubling on a first sync and deleted bookmarks being synced back.
- Fixed some pages failing to launch an app after misdetecting the system platform; pages such as the China Mobile campaign page now open normally from the cross-platform entry.
- Fixed the video assistant play/pause button not refreshing.
- Fixed the address bar paste row's background in dark mode.
- History is grouped by device, so a browser update or reinstall no longer adds duplicate entries, and a shortcut to open Aira history is added.

## 3.0.2 (1000410)

2026-09-11

This release speeds up Huawei Cloud Space sync, straightens out extra backup, and adjusts the Aira Pro plans and interface material.

- Huawei Cloud Space syncs bookmark and history deletions incrementally, reducing stutter and full re-uploads.
- Extra backup uses WebDAV only and writes from this device, instead of being merged as a second sync source.
- Aira Pro keeps only the ¥1 monthly subscription and the ¥7.89 yearly subscription, dropping the long-term membership and the quarterly subscription.
- The browser glass surface and the novel reading action bar blur the content behind them; home shortcut tiles become opaque for smoother scrolling.
- Fixed settings home being covered by the title bar and "More" not responding while editing history.

## 3.0.1 (1000408)

2026-09-10

This release upgrades bookmark sync to v4, rebuilds the bottom toolbar and interface material, and adopts a new icon language.

- Bookmark sync is upgraded to v4, making cloud recovery and switching more stable.
- The bottom toolbar becomes a system-style panel with drag reordering and more responsive gestures.
- The glass material and scrolling behavior of the tab, home, and settings top bars are more stable.
- History becomes its own search page, and the custom home preview is easier to tap.
- The app icon becomes a new outline icon set, making settings and toolbar entries easier to tell apart.
- The open-source distribution and the Official edition share one source tree; the Community edition does not include the official cloud or the HUAWEI ID.

## 2.6.1 (1000369)

2026-08-30

This release focuses on the back and switch experience for new tabs, reducing blank frames and stale pages during page changes.

- Back navigation after opening a new tab from a page is improved, returning to the source tab more reliably.
- Fixed a brief blank frame when going back from a child tab, making page restore more continuous.
- The old web surface is hidden in time when opening and switching tabs, reducing stale page flashes and overlapping content.

## 2.5.3 (1000366)

2026-08-29

This release focuses on startup and home page restore, and improves fullscreen video, web media, and regional site compatibility.

- Startup scheduling is optimized, moving work that is not needed for the first frame to a background warm-up stage, cutting unnecessary waiting when opening Aira.
- Fixed custom home page shortcut icons restoring and refreshing after a cold start, reducing missing icons and repeated loading.
- Fullscreen video, orientation switching, and web player takeover on large screens are improved, falling back more reliably to the existing compatibility path when they fail.
- Fixed HTTP video, posters, and background images sometimes not showing on HTTPS pages, and added web identity compatibility for Google regional sites.
- Large-screen settings titles and an unnecessary clipboard permission are trimmed, reducing repeated information and permission requests.

## 2.5.2 (1000360)

2026-08-29

This release rebuilds the PC settings experience and further improves page loading, userscripts, the video toolbar, and download feedback.

- PC settings are rebuilt as a stable two-column workspace, with consistent width, text, corners, titles, and scrollbars across first-, second-, and third-level pages.
- Aira Pro on PC is merged into the right side of settings, the horizontal theme preview is refreshed, the privacy protection chart is improved, and settings that do not apply on desktop are removed.
- The page's first frame, scroll response, userscript rule projection, and the `document-end` / `document-idle` timing are optimized, cutting waiting when opening a page.
- Fixed video toolbar discovery, control, and exit restore for nested iframe players, making complex video pages more reliable to operate.
- Downloading tasks get clearer ring progress feedback, and the external app search entry is off by default.

## 2.5.2 (1000358)

2026-08-28

This release adds local backup and focuses on quick search, home search, userscripts, and large-screen browsing, making startup, search, and everyday use smoother and more reliable.

- Local backup import and export are added, letting you check the contents and choose what to restore, making it safer to move and keep browsing data.
- QuickSearch cold starts, pressing Enter to search on the home page, and first-frame feedback are optimized, so pages open faster and more smoothly with many userscripts.
- The userscript runtime and document lifecycle are hardened, and fixed editing a script with a hardware keyboard on a large screen blocking further installs.
- The download core and built-in translation batching are upgraded, improving file handling, the clipboard permission, and stability on complex pages.
- Foldable and large-screen interface states connect better, and the Huawei system rating dialog replaces the custom prompt.

## 2.5.1 (1000352)

2026-08-27

This release focuses on large-screen and foldable experience, search submission speed, web media discovery, and navigation safety, making complex pages smoother and more stable.

- Large-screen and foldable mode switching, settings layout, and the cold-start first frame are optimized, reducing flicker, misalignment, and waiting when the window changes.
- Search submission and page runtime scheduling are optimized, cutting first-open waiting with many userscripts and improving fallback navigation, Bing back behavior, and mobile redirect chains.
- Video and media resource discovery is upgraded to prefer playable content, reduce duplicate noise, keep key resource details, and gather takeover actions in the page toolbar.
- Page safety and the bookmark experience are strengthened, blocking unsolicited cross-site jumps while keeping legitimate mobile redirects, and the bookmark root folder can be switched.

## 2.4.2 (1000348)

2026-08-26

This release focuses on HTTPS-first access and HTTP fallback, and improves Huawei Cloud Space history sync and home page cold starts.

- HTTPS-first access and HTTP fallback are improved, so a confirmed HTTP choice is remembered reliably, reducing repeated confirmations and unexpected jumps.
- Fixed the reset and clear flow for site security settings, so HTTP access exceptions are cleared and applied again as expected.
- Huawei Cloud Space history sync is optimized, keeping bulk storage, encoding, and merge work in the background so browsing stays smooth during sync.
- Unchanged Huawei Cloud Space syncs do less repeated work, and the home favorites area has a stable cold-start layout and first frame.

## 2.4.2 (1000346)

2026-08-25

This release focuses on Huawei Cloud Space bookmark sync, ad blocking startup and switch consistency, and more reliable home icons and failure diagnosis.

- Huawei Cloud Space bookmark storage uses bounded chunks with a clearer confirmation flow, so large bookmark libraries sync more reliably and cloud storage grows more predictably.
- Fixed the ad blocking master switch getting out of sync while the browser runs, updates rules, or refreshes the proxy; turning it off no longer keeps filtering.
- Ad blocking cold starts are optimized to safely reuse verified persistent rule state, cutting the time the first page waits for repeated rule checks and merges.
- Home favorite icons load on the first frame and restore their state better, reducing missing, late, or inconsistent icons at startup.
- Key report details from before and after a crash are combined, making the failure context more complete and easier to diagnose.

## 2.4.2 (1000343)

2026-08-25

This release focuses on opening external content, HTTP site access, search, and downloads, and makes sync and failure diagnosis more reliable.

- An explicit choice to use HTTP is remembered per site, reducing repeated confirmations on the same site while keeping private sessions and certificate warnings separate.
- Fixed Aira briefly flashing back to the home page when opened from an external link, shared content, or a supported file, and tightened file associations so unsupported HAP files are not offered.
- Fixed manually importing or enabling custom blocking rules wrongly triggering a membership privacy check; free manual rule actions no longer show an unrelated membership prompt.
- Search submission, page runtime startup, and network availability checks are optimized, and download task state recording and recovery are strengthened, reducing waiting and unexpected stops.
- Fixed identity conflicts in Huawei Cloud Space history sync, and key state before a crash is recorded better, improving sync safety and failure diagnosis.

## 2.4.1 (1000339)

2026-08-23

This release adds cross-device history sync and failure diagnosis controls, and further improves background restore, site compatibility, and large-screen browsing.

- Incremental history sync is added, continuing your account history timeline across devices through Aira Cloud or Huawei Cloud Space.
- Sync source switching, account changes, and retries are improved, making history migration and merging more consistent.
- Automatic failure diagnosis is added with a clear user consent switch, so you control diagnostic collection and get help finding problems.
- Background running and page state restore are optimized, reducing broken pages and stopped scripts when you return to the app.
- The security-signed site compatibility policy is updated, and large-screen settings, novel page turning, and the history list get better layout and separators.

## 2.4.0 (1000338)

2026-08-17

This release completes the latest site compatibility policy and improves large-screen settings and novel reading, making sure finished improvements reach the official build.

- A security-signed cloud policy for site user agents is added, updating compatibility rules for specific websites more promptly while keeping built-in rules as a reliable base.
- Cloud compatibility policies get validity checks, local caching, and fallback, so browsing stays stable when the network fluctuates or a policy is unavailable.
- The large-screen settings sidebar has better scrollbar spacing, so menu content and the scroll area no longer squeeze each other.
- Vertical novel reading on large screens supports swiping in the blank areas beside the text, keeping the same text width and reading layout.

## 2.3.0 (1000323)

2026-08-17

This release focuses on novel reading, large-screen dialogs, userscript compatibility, and search under a custom user agent, making complex pages and long reading more stable.

- Novel reading gains finer line-level pagination and Chinese punctuation boundary handling, reducing page jumps and improving continuity in long texts.
- Book anchors, chapter positioning, and reading progress restore are optimized, so you return to your last spot more reliably even after the page structure changes.
- The novel reading dialog and system surfaces adapt to large screens, so reading controls are clearer and space is better used when the window resizes.
- Userscript matching behaves more compatibly, and script injection and runtime cleanup are improved, reducing scripts failing or running twice on different pages.
- Fixed quick search being switched wrongly under a custom user agent, so site compatibility mode and common search entries work together.

## 2.3.0 (1000314)

2026-08-14

This release focuses on a new ad blocking core and improves safe navigation, site compatibility, and page reloads, making filtering more efficient and browsing more stable.

- Ad blocking moves to a new Rust core that handles network requests, rule subscriptions, redirected resources, and page element filtering together, working more efficiently on complex pages.
- Ad filter rule loading and state restore are optimized, reducing interference from old state, repeated work, and leftover ads on the page.
- HTTPS-first navigation is improved: a URL without a scheme tries a secure connection first and falls back reliably when the site does not support HTTPS.
- Site user agent settings apply and restore better, so mobile, desktop, and per-site compatibility modes stay stable across navigation and reloads.
- The address bar and browser runtime state connect better, reducing problems on special pages, reloads, and compatibility switches.

## 2.2.0 (1000306)

2026-08-13

This release focuses on large-screen multi-tab browsing and fixes video pages, site compatibility, and third-party home page interaction.

- Large screens gain a Chrome-style tab list for viewing, switching, and closing tabs in one place, making multi-tab management clearer and faster.
- The active tab, address bar editing, search focus, and closing the tab list work together better, so state is more accurate when switching pages and typing a URL.
- Large-screen dialog layout and the full-screen mask are improved, reducing display problems when the window changes, a dialog opens, or the background is used.
- The video page behavior bridge is restored, fixing video detection and takeover being unavailable on some pages.
- The user agent compatibility policy for verified sites is restored, and the third-party home page toolbar is visually stable when collapsed.

## 2.1.1 (1000299)

2026-08-12

Improved the visual appearance of third-party home pages.

## 2.1.0 (1000298)

2026-08-12

This release focuses on large-screen browsing and the userscript experience, making the window layout tighter, page display and back navigation more stable, and script data read and write more efficient.

- Large-screen tabs merge into the system title bar, freeing more room for pages, with better window resizing, title bar display, and interaction stability.
- Fixed the bottom of a large-screen page being covered and the top browser area losing context, so page layout is more reliable after a window change.
- Long titles in the desktop bookmarks bar display better, so bookmark names no longer squeeze other actions or break the layout.
- Userscript value storage is rebuilt with per-script isolation and atomic writes, reducing write cost and the risk of data corruption during frequent updates.
- Fixed the page back cache breaking in native user agent mode, and improved the userscript bridge and runtime state restore.

## 2.0.0 (1000283)

2026-08-10

This is the Aira 2.0 release, upgrading privacy protection, site controls, desktop browsing, and video compatibility, making your security state clearer, common actions more complete, and playback on complex pages more stable.

- A privacy protection center is added, combining enhanced tracking protection, HTTPS-first, fingerprint protection, cookie management, and seven-day protection stats, so your security state and settings are clearer.
- Site controls are upgraded to manage permissions, user agent, external navigation, and page security policy per website, and you can add sites that need their own configuration.
- Large-screen browsing gains a desktop bookmarks bar and a configurable forward button, and web apps can hide the browser interface, making bookmarks, navigation, and immersion easier.
- Video compatibility settings and playback detection are upgraded, improving video discovery, takeover, and ongoing support on complex pages such as YouTube, Bilibili, Weibo, and XlPlayer.
- Page protection feedback, tablet and large-screen page fit, userscript data saving, and the risk confirmation screen are improved, and stability issues with home shortcuts, desktop card refresh, and large-screen bookmarks bar layering are fixed.

## 1.1.3 (1000261)

2026-08-07

This release expands custom home pages and download sharing, and improves page protection feedback and desktop card display, making home page actions, page safety awareness, file sharing, and desktop entries more complete.

- A custom home page can open the browser toolbar directly and call common actions such as My Bookshelf and the private mode confirmation.
- A home bridge ready notice is added, fixing buttons staying unavailable after the page loads in some imported home pages.
- The official minimal home page example and developer guide are updated with better feature detection, initialization, and toolbar calls.
- Sharing a downloaded file matches system share targets by its real file type, so PDFs, images, documents, and media find a compatible app more easily.
- The desktop search card gets a clearer transparent outline, navigation arrows, and layouts for different sizes, with better separation between content and background.
- The page protection report shows blocked requests, cleaned links, and hidden elements on this page, and the address bar briefly shows the protection count.
- Protection stats use a new action measure; old stats that cannot be converted reliably reset to zero without affecting rule subscriptions, switches, or site exceptions.

## 1.0.15 (1000255)

2026-08-06

This release focuses on novel reading and large-screen use, and improves web video casting and page navigation stability.

- Novel mode detection is more accurate, supports more chapter numbering styles and dynamic pages, and triggers less often on pages that are not for reading.
- Large-screen novel reading gains a two-page layout, the bookshelf adjusts content density to the window width, and paginated text no longer overflows at the bottom.
- Novel covers and book details are detected better, keeping valid content even when site rules are incomplete or page details change.
- Video takeover restores the native casting entry, keeps the current playback page while casting, and improves loading states and compatibility with common media requests.
- The large-screen Aira Pro dialog displays better, and fixed the address and page state getting out of sync after navigation on a dynamic page.

## 1.0.15 (1000249)

2026-08-05

This release upgrades the site information shown in the tab overview and fixes stability issues in page navigation and PDF downloads.

- The tab overview gains clearer site icons, site names, and page title hierarchy, making similar pages easier to tell apart.
- Tab card entry, selection, close, and swipe feedback are improved, with smoother thumbnail and card state changes.
- Fixed a failed page preload wrongly overwriting the current page, hiding quick search, or polluting the tab address.
- Fixed the built-in PDF reader download button sometimes not responding or reporting a failure; after confirming, the download completes and the file exports normally.

## 1.0.15 (1000245)

2026-08-05

This release improves smart grip support for custom home pages, so imported home pages respond more reliably when the way you hold the device changes.

- Fixed grip state changes no longer triggering callbacks after the custom home bridge refreshes, making left-hand, right-hand, two-hand, and default switches more stable.
- The official minimal home page example is updated to show how to adjust the common area layout to the current grip.
- The custom home page developer guide is improved with grip listening, default layout, and unsubscribing, helping home page packages stay compatible.

## 1.0.15 (1000243)

2026-08-04

This release improves the first-time Huawei Cloud Space experience and further hardens bookmark sync consistency.

- Turning on Huawei Cloud Space sync for the first time shows clear reading and setup progress, so you can safely leave the page after saving and let it finish in the background.
- When reading sync state fails, you get a clear explanation and a retry entry, and an ordinary read failure is told apart from a Huawei Cloud Space settings confirmation failure.
- Bookmark merge normalization is improved: when a live bookmark or folder clashes in ID with a deletion record of the opposite type, valid content is kept.
- Fixed snapshot validation failing on a cross-type deletion record clash, reducing interrupted syncs and the spread of unexpected deletion records.

## 1.0.14 (1000242)

2026-08-04

This release hardens data safety and setup for multi-source sync, and improves dynamic novel pages and browsing panels.

- Switching between Aira Cloud, Huawei Cloud Space, and WebDAV preserves bookmarks, folders, and order more safely, reducing content loss from deletion conflicts.
- Bookmark deletion history, snapshot validation, and cloud confirmation are improved, making cross-device sync, retries, and first-time setup more reliable.
- The sync page's first read and the Huawei Cloud Space activation flow show clearer status, avoiding blank content during setup.
- Personalization sync is improved to prefer the newer toolbar order when several devices change it.
- Text and chapter detection is stronger on dynamic single-page novel sites, and fixed taps in the URL panel mask area.

## 1.0.14 (1000238)

2026-08-03

This release upgrades comics and reading, secure DNS, userscripts, and ad blocking, and improves bookmarks, downloads, and everyday large-screen browsing.

- Comic and novel detection, chapter image loading, reading position restore, and source site sign-in prompts are strengthened, and more pages enter reading mode well.
- Secure DNS supports creating, naming, editing, and switching several custom profiles, its large-screen management screen is improved, and upgrading from older profiles migrates correctly.
- Userscripts can be imported from system files and external pages, and system share links, the address long-press menu, and bookmark drag reordering work better.
- Ad blocking third-party rules, page element hiding, cold starts, and Ping request handling are optimized, running more smoothly on complex pages.
- Download confirmation, desktop shortcuts, large-screen dialogs, tab titles, and input focus are improved, and membership state and everyday browsing are more stable.

## 1.0.14 (1000231)

2026-08-02

This release focuses on comics and reading mode, secure DNS, and userscript import, and keeps improving ad blocking and everyday browsing.

- Comic and novel detection, chapter image loading, reading position restore, and source site sign-in prompts are strengthened, so more sites enter reading mode reliably.
- Secure DNS supports creating, naming, editing, and switching several custom profiles, making common services easier to manage.
- Userscripts can be imported from system files and external pages, and system share links open in the browser more reliably.
- Ad blocking third-party rules, page element hiding, cold starts, and Ping request handling are optimized, running more smoothly on complex pages.
- The address long-press menu, large-screen dialogs, tab title refresh, and input focus are improved, making common browsing actions more stable.

## 1.0.13 (1000216)

2026-07-31

This release improves novel bookshelf sync, secure DNS, privacy protection, and interface customization, and keeps reading and everyday browsing stable.

- Novel bookshelf and reading progress sync are added, continuing your shelf and reading position across supported sync sources.
- Secure DNS configuration and automatic selection are added, and private mode, site permissions, and ad blocking run more stably.
- Toolbar buttons can be customized, and switching a phone to the desktop interface asks for confirmation, making settings safer.
- Novel chapter caching, scrolling, and restore are improved, and reading mode detects content better on pages such as Baidu Baike.
- Page runtime, media handling, and ad filtering are hardened, reducing jank, misjudgment, and state errors on complex pages.

## 1.0.13 (1000211)

2026-07-30

This release brings a complete browsing experience for large-screen devices and upgrades novel reading, ad blocking, video takeover, and everyday browsing stability.

- A browsing layout for tablets and 2-in-1 devices is added, with a top tab bar, address bar, bookmark and history workspace, page zoom, and large-screen settings.
- Novel reading and the bookshelf are upgraded with better chapter detection, table-of-contents paging, reading controls, resume, and cloud rule updates.
- Ad blocking rule compatibility is stronger, supporting more AdGuard and EasyList China rules, wildcard matching, initial page hiding, and POST request blocking.
- Web video detection and takeover are rebuilt, making nested pages, multi-video pages, and the floating takeover entry more accurate and stable.
- Common flows such as the bottom toolbar, search panel, tab transitions, download recovery, and userscript install are optimized.

## 1.0.12 (1000203)

2026-07-26

This release focuses on the userscript install and management experience, and improves the bottom tools panel, in-page find, element inspection, and home page display.

- The userscript install and management interface is upgraded, with more consistent install confirmation, page actions, and script grouping, and clearer buttons and icons.
- Fixed the bottom toolbar collapsing and transitioning badly when opening panels such as find and media resources, so panels show and close more reliably.
- The in-page find entry is restored and improved, with a consistent material, icons, and feedback on the floating find bar.
- Element inspection shows fuller HTML, and home text, shortcuts, and icons are easier to read over a wallpaper.
- The proxy form avoids the keyboard better, and the background setup status after switching Huawei Cloud Space bookmarks is clearer.

## 1.0.12 (1000199)

2026-07-26

This release polishes the bottom toolbar, multi-tab management, and cross-app search, and further improves Huawei Cloud Space bookmark sync stability.

- Expanding, collapsing, and reordering bottom toolbar actions are upgraded, with more stable and natural feedback while dragging and tapping.
- The floating address bar, search mask, and return-to-home animation are optimized, reducing jumps and visual leftovers while collapsing.
- Closing tabs and the empty state on the tab manager page are improved, prompting you and returning home smoothly when no tabs are open.
- Fixed navigation from Youdao cross-app search results, so the search entry opens the matching mobile result more completely.
- Huawei Cloud Space bookmark sync is hardened for first setup, background retries, and large bookmark libraries, recovering more reliably after an interruption.

## 1.0.11 (1000168)

2026-07-24

This release keeps hardening video playback, page content inspection, and common browsing actions, and improves script data, compatibility, and file handling.

- The video helper layer and casting picker coordinate better: the control bar stays usable while casting and restores automatically when it ends.
- Element inspection and hiding are improved with better element selection, code preview, and panel interaction, making content control more stable.
- Fixed userscript GM data not persisting across pages and reloads, reducing lost script settings.
- The default Android user agent, quick search engine switching, and Huawei file opening are optimized for better page compatibility and easier use.
- Fixed drag position being lost after scrolling the bottom toolbar, making toolbar customization more stable.

## 1.0.10 (1000162)

2026-07-24

This release focuses on web video, quick search, and tab actions, and improves custom home page import, the bottom toolbar, and page content control.

- Cross-frame video discovery and playback takeover are stronger, video detection is more stable on complex video sites, and playback control icons and takeover prompts are improved.
- Quick search engine switching is easier, and your search text is kept while pages switch and initialize.
- The tab overview, bottom action bar, and toolbar scrolling are optimized, with better tap targets, press feedback, bookmark actions, and custom slots.
- Importing a custom home page package from outside is improved, search state and search engine display are fixed, and home-related settings can sync.
- Page element hiding, userscript compatibility, offline membership detection, and common icons are improved, reducing problems on complex pages and unusual networks.

## 1.0.10 (1000156)

2026-07-23

This release focuses on web video detection, tab management, and bottom bar actions, and improves custom home pages, userscripts, and content control.

- Cross-frame video discovery and playback takeover are stronger, video detection is more stable on complex video sites, and playback control icons and takeover prompts are improved.
- The tab overview gets a clearer bottom action bar, with better tab switching, clear actions, empty state, and private tab handling.
- Bottom toolbar and address actions get better press feedback, tap targets, bookmark actions, and icons, making common actions more stable.
- Fixed custom home page search state and search engine display, and home-related settings can sync.
- Element hiding selection, userscript compatibility, and offline membership detection are improved, reducing problems on unusual networks and complex pages.

## 1.0.9 (1000152)

2026-07-22

This release focuses on Huawei Cloud Space bookmark sync and improves userscripts, search, multi-tab, and privacy.

- Huawei Cloud Space bookmark sync moves to structured storage with better first upgrade, deletion propagation, retries, and state restore, making cross-device sync more reliable.
- Userscript install, management, and running are hardened, GM data persists reliably, and state is lost less often after a restart or page switch.
- The desktop search card, cross-app search paging, and search text retention are optimized, making common search entries easier.
- Tab creation, switching, closing, restore, and bottom panel sessions are improved, making back navigation and multi-tab browsing more stable.
- Common action icons are unified, and site icons, download actions, landscape search, and private mode details are improved.

## 1.0.7 (1000139)

2026-07-18

This release adds one-tap search from the home screen and cross-app search, and further improves reading panels, back navigation, and sync state.

- A 1×2 "one-tap search" home screen service card is added, going straight to search from a cold start or from the background.
- Configurable cross-app search is added, supporting more third-party app keyword entries with adjustable order.
- Session handling for reading mode, offline reading, and browser panels is optimized, reducing panel conflicts and leftover state.
- Fixed back navigation across tabs, search engine summary refresh, Markdown document display, and desktop shortcut icons.
- Sync state for bookmarks, activity records, and personalization settings is hardened, and WebDAV remote state detection is improved.

## 1.0.5 (1000136)

2026-07-16

This release improves the home page and shortcut entries, and strengthens custom home page capabilities, browsing immersion, and first-sync reliability.

- Native and custom home page settings are regrouped, with clearer large-screen layout and wallpaper choices.
- The custom home page gains a developer guide, a minimal template, and interfaces for choosing and reordering native shortcuts.
- Home shortcut compact layout, folder navigation, icon display, and drag-order sync are optimized.
- Top-of-page immersion, home scroll bounce, and the bottom toolbar follow effect are improved.
- Fixed a state handover issue when sync is turned on for the first time, improving cross-device sync reliability.

## 1.0.4 (1000135)

2026-07-15

This release further improves system search on custom home pages, making the search entry, search engine choice, and history suggestions more stable.

- A custom home page can enable system search on its own.
- The custom home page search entry, input focus, and back behavior are improved.
- System search, custom search engines, and the home search interface work together better, with clearer fallback rules.
- Fixed the suggestion list not refreshing after search history is deleted.

## 1.0.3 (1000134)

2026-07-15

This release focuses on personalization sync and search configuration across devices, and improves bookmarks and sync source switching.

- Personalization sync now covers home shortcuts, core preferences, the activity heatmap, and custom search engines.
- Custom search engines and custom home pages work together better.
- Primary sync source switching is improved, reducing unnecessary backup relationships.
- Fixed the list not refreshing after renaming a bookmark or folder.
- A feedback group entry is added, making it easier to report issues and talk with others.

## 1.0.1 (1000132)

2026-07-14

This release keeps improving common browsing and stability.

- Search, web video, and icon display are improved.
- Startup and page loading are improved.
- Fixed several small issues.

## 1.0.0 (1000130)

2026-07-13

Aira 1.0.0 is officially released with a more stable and easier browsing experience.

- Multi-tab browsing and back navigation are improved.
- Video playback and common tools are improved.
- Membership and sync are improved.

## 0.2.13 (1000122)

2026-07-11

This release keeps improving multi-device use and multi-tab browsing, and makes common actions more stable and consistent.

- The overall sync and personalization experience is improved.
- Tab management, page switching, and back navigation are improved.
- Search, web apps, and everyday browsing are more reliable.

## 0.2.11 (1000120)

2026-07-09

This release keeps polishing the browser's look and common actions, making bottom actions, tab management, and page switching more stable and smooth.

- Bottom search, the address bar, and floating browser controls look and behave better.
- The tab overview, return to home, and page switching transition more smoothly.
- Everyday browsing is more consistent and reliable.

## 0.2.10 (1000119)

2026-07-09

This release keeps polishing common browser interactions, focusing on bottom floating search, back navigation, and stability while using multiple tabs.

- The bottom floating search and the address bar surface look better.
- Back navigation, tab closing, and the back fallback after a window opens are improved.
- Multi-tab browsing and everyday actions are more reliable.

## 0.2.9 (1000118)

2026-07-09

This release mainly improves overall stability, smoothness, and common features, reducing problems with multiple tabs, return to home, video playback, and sync.

- Multi-tab browsing, background keep-alive, and page restore are optimized, making everyday switching more stable.
- The home page, bottom toolbar, search, and tab overview behave better.
- Web video detection, playback takeover, and resource handling are stronger.
- Membership, sign-in state, sync, and settings flows are optimized.
- Some old experimental entries and outdated logic are removed, making the browser more reliable.

## 0.1.16 (1000049)

2026-06-30

This release hardens the bottom browsing toolbar and panel actions, making common actions in search, reading, offline viewing, and tab management more stable.

- Bottom toolbar actions now show a correct available state, so buttons match the current page more often.
- The bottom search panel opens, closes, and routes actions more reliably during repeated use.
- Bottom action entries in reading mode and offline pages are improved, so common commands show up more reliably.
- The tab overview entry and bottom background layer are adjusted, making multi-tab switching smoother.
- The bottom panel area is more robust, so future updates are less likely to break it.

## 0.1.15 (1000048)

2026-06-29

This release keeps polishing the bottom browsing panel, the tab overview, and settings, and switches the default app icon to a new light style.

- The default app icon becomes a light style, with dark, blue, and other styles still selectable in app icon settings, removing duplicate options.
- The bottom search panel, toolbar actions, and layout stability with the keyboard open are optimized, making typing and switching smoother.
- Tab overview previews, the return-to-home animation, and bottom browser chrome dragging are improved, making tab cleanup more stable.
- Settings detail pages, the search entry, and some appearance options are tidied up, making common settings easier to find.
- Reading mode, offline pages, and sync details are improved, reducing jank and state jumps in everyday browsing.

## 0.1.14 (1000047)

2026-06-28

This release focuses on the lightweight bottom toolbar, the tab overview, cross-device sync, and startup performance, making everyday browsing, tab management, and restoring settings smoother.

- The lightweight bottom toolbar's dragging, expanding, collapse hint, and address bar panel are optimized, feeling more natural while browsing.
- The tab overview, tab closing, and bottom panel mask are improved, making switching and tidying pages more stable.
- Personalization sync and the first-time sync flow are improved, restoring search, home shortcuts, and common preferences across devices more reliably.
- The bookmark sync lifecycle, folder selection, and bookmark and history management are stronger, making large bookmark libraries easier to handle.
- Web video probing, startup maintenance, and background running are optimized, reducing extra load when opening ordinary pages.

## 0.1.13 (1000046)

2026-06-28

This release keeps polishing page translation, custom home pages, bookmark management, and the in-app proxy, making complex pages, cross-device setup, and proxy authentication more stable.

- The in-app proxy handles domain names better: proxy authentication recognizes the resolved IP, so entering a domain works as well as entering an IP.
- The page translation panel, language detection, and batch translation are optimized, making translation on complex pages more stable with clearer settings entries.
- Remote preview and caching for custom home pages are improved, reducing stutter while previews generate, sync restores, and remote resources load.
- Bookmark folder selection, list scrolling, and immersive interface details are polished, making large bookmark libraries easier to manage.
- Themes, membership benefits, sync compatibility, and page runtime details are improved for more stable everyday browsing.

## 0.1.12 (1000043)

2026-06-26

This release focuses on the membership center, invite codes, and personalization sync, and keeps bookmark cloud sync smooth, making cross-device setup and benefit management easier.

- Personalization cloud sync is added, syncing search, home shortcuts, core preferences, and some personalization settings, so switching devices is easier.
- The membership center and invite friends page are reorganized, with clearer invite codes, benefit descriptions, and restore purchase entry.
- Bookmark cloud sync's incremental writes, snapshot cleanup, and merging are optimized, making large bookmark libraries sync more smoothly.
- Sync settings get finer sync scopes and better organized entries, making bookmark and personalization sync status easier to understand.
- Proxy and sync cooperation is polished further, reducing uncertainty when switching configurations and restoring across devices.

## 0.1.11 (1000042)

2026-06-25

This release reorganizes settings and keeps improving bookmark sync, custom home pages, and everyday browsing, making common settings easier to find and cross-device use more stable.

- Settings are regrouped into clearer entries: Common, Privacy and security, Site settings, Appearance and toolbar, Web features, Web apps, Laboratory, and Advanced.
- A custom URL home page gains a "try to force dark mode" switch for more comfortable night browsing, switchable off if a page displays badly.
- The bookmark sync flow is optimized, with more stable incremental sync, WebDAV sync, and desktop bookmark sync.
- Desktop sign-in, Chrome bookmark sync, and sync center status display are improved, making cross-platform migration and backup easier.
- Settings navigation, search, and detail display are polished for phone and large-screen layouts, reducing confusing entry levels.

## 0.1.10 (1000041)

2026-06-24

This release keeps polishing settings, bottom toolbar gestures, and the search, bookmark, and history experience, making browsing and configuration easier.

- Settings gain a clearer About overview, and the theme preview and detail pages are more stable when switching between light and dark.
- The bottom toolbar panel, quick actions, and dragging are optimized: buttons are easier to see, and swiping from the edge to return home shows a guide.
- Search suggestions, page translation site rules, and app proxy prompts are improved, making common settings easier to understand and apply.
- Bookmark and history list performance, row spacing, and status display are optimized, making large amounts of browsing records and bookmarks smoother to manage.
- Fixed details such as membership referral status refresh, encoded redirect URLs, and bottom panel animation, improving everyday stability.

## 0.1.9 (1000040)

2026-06-23

This release focuses on membership invites, web apps, custom home pages, and everyday browsing stability, making common features more complete and reassuring.

- A fixed invite code and a free Pro flow are added: after a friend redeems it for the first time, both of you get 15 days of Aira Pro.
- The membership page benefit comparison and subscription prompt are improved, making default Club benefits clearer and Pro a more on-demand choice.
- Web app settings, desktop entries, and the empty state are improved, making added web apps easier to manage.
- Custom home page remote loading, offline caching, and preview are improved, making startup and return to home more stable.
- Web video takeover, fullscreen, private mode data retention, bookmark and history actions, and the content filtering confirmation flow are optimized.

## 0.1.8 (1000039)

2026-06-21

This release keeps polishing page display, video playback, script compatibility, and desktop app entries, making common sites and everyday browsing easier.

- Built-in high-resolution icons are added for installing common sites as apps, making desktop entries for Instagram, YouTube, Telegram, X, Discord, Reddit, Facebook, and Threads clearer.
- The page top safe area, loading progress, and system font scaling are optimized, making page display and reading more stable.
- Web video takeover and fullscreen interaction are improved, so playback controls and the browser interface return more naturally.
- Userscript storage, the page translation menu, the mobile user agent, and download file extensions are strengthened.
- Content filter subscriptions and rule handling are hardened, making complex subscription sources import and run more reliably.

## 0.1.7 (1000038)

2026-06-21

This release focuses on page translation, bookmark import and sync, page display, and membership, making everyday browsing steadier and easier.

- Aira system translation moves to our own service, with better support for translating large batches of page paragraphs.
- Page text size adjustment is added, making it faster to change the font scale while reading different pages.
- Bookmark import, conflict handling, and large-data sync are optimized, making complex bookmark libraries sync more reliably.
- Userscript compatibility is improved, supporting settings read and write for scripts such as KISS Translator.
- A dynamic app icon and smart grip tab actions are added, and membership benefit prompts and the pre-purchase sign-in flow are improved.

## 0.1.6 (1000037)

2026-06-20

This release keeps improving common browser features, making playback, search, the home page, and prompts easier to use.

- Web video playback is improved, and the browser interface restores more reliably after the playback overlay closes.
- Long-press actions for images are added, making it easier to save and handle images on a page.
- The translation prompt display and gestures are optimized, so it appears and dismisses more naturally.
- Search engine configuration and content filter rule handling are improved, working more smoothly in complex cases.
- Home page interaction details are adjusted, and a QQ group entry is added for feedback and discussion.

## 0.1.5 (1000036)

2026-06-20

This release upgrades membership, invite codes, and bookmark sync, and completes key experiences before the official release.

- Membership, invite codes, and Pro status restore are handled by Aira's own service, making status sync more stable.
- Bookmark cloud sync is saved through Aira's own service, making sync more reliable.
- Switching the basic service mode now asks for confirmation, reducing mistakes.
- The changelog supports dark mode, making it more comfortable to read at night.

## 0.1.4 (1000035)

2026-06-19

This release relaxes the common feature limits of Aira Lite, so ordinary users who installed the app naturally can use the browser more fully.

- Aira Lite now supports up to 10 offline pages, 5 userscripts, and 30 manual hiding rules.
- Aira Lite can now enable WebDAV bookmark sync, and using your own WebDAV service no longer needs an invite code.
- Aira Lite can now use up to 2 locally imported content filter rule sources, and the Aira Club local rule source allowance rises to 5.
- The membership comparison table is updated with the new Lite, Club, and Pro allowances.
- Downgrading or refreshing benefits no longer turns off WebDAV sync just because you are on Lite, and local rule sources are kept to the new Lite allowance.

## 0.1.3 (1000034)

2026-06-18

This release fixes a touch problem at the top of the home page, and completes membership invites, the rating entry, and the fullscreen video experience.

- Fixed an area at the top of the home page not responding to taps, restoring touch on the favorites drawer and top entries.
- A temporary fix for that touch problem that never took effect is removed, reducing the chance of later issues.
- When signed out, the profile card in settings and on the membership page now clearly says "signed out", so you do not mistake it for having membership benefits.
- The membership invite page explains how to get an invite code and shows the HUAWEI ID sign-in panel first when sign-in is needed.
- The About page gains a "rate us" and QQ group entry, with a more restrained app market rating prompt.
- Fixed how some portrait web videos enter fullscreen, letting the page's own fullscreen take priority.

## 0.1.2 (1000032)

2026-06-17

This release fixes the home page layout and tap experience after a portrait/landscape switch, keeping the favorites area stable for now.

- The safe area and home rebuild after a portrait/landscape switch are optimized, reducing mismatches between where favorites look and where taps land.
- Top safe area handling on the home page is adjusted, so the system home page no longer doubles up on top safe area spacing.
- The home favorites area is temporarily fixed in the expanded state, keeping the expand arrow but turning off tap-to-collapse and press feedback, so a mistap does not look like nothing happened.
- The changelog display in settings is added, reading the current version from the installed package so each release's changes can be recorded.

## 0.1.1 (1000031)

2026-06-17

This is the version record before this round of home page fixes, kept for later comparison and reference.

- Records 0.1.1 as the baseline before the fix for the home favorites tap issue.
- Later releases add new records at the top of this list, and older logs are no longer overwritten.

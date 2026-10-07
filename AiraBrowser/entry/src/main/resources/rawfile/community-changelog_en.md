# Changelog

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

This release adds a custom download location, turns desktop download settings into a centered dialog, and fixes lost sign-in state, misplaced tab previews, and third-party home page cold starts.

- Download settings become a centered dialog on desktop with a title bar, and sub-pages can navigate back inside the dialog.
- The download location can be set to a folder of your choice, and later ordinary downloads save there; private downloads still follow the private settings.
- The download confirmation uses the existing file-type icons and lets you change the save location before confirming.
- The desktop toolbar menu is reorganized: history, bookmarks, downloads, page tools, and settings open from one place.
- Settings list icons get a colored background, consistent with the existing icon resources.
- Centered dialogs use an opaque themed surface, so scrolled content no longer shows the page behind it.
- Cookies are saved immediately before going to the background or swiping the app away, so a site you just signed in to does not lose its session.
- Fixed the tab preview being replaced with the top of the page after a tab is collapsed or sent to the background.
- Fixed a third-party home page flashing white on a cold start, showing light colors first, and covering the page when pulling up the search.

## 3.3.1 (1000448)

2026-09-21

This release makes the tab style a three-way choice and fixes downloads and in-page navigation disturbing tab state.

- "Tab style" in Appearance now offers three layouts: tiled cards, large horizontal cards, and stacked, defaulting to tiled cards and switchable at any time.
- Fixed the current card disappearing and reappearing when entering the tab overview in the large horizontal card layout.
- Fixed the middle bar occasionally flashing the tools panel and then dismissing it on swipe up; swipe up and the "Tabs" button now share one decision.
- Fixed a bypass download such as an ad sending the page you are reading back to an old URL and reloading it, and the same download no longer notifies twice.
- Fixed reopening that tab after an in-page navigation (anchor, History API, single-page app route) returning to the old page.
- Fixed the quick search row disappearing after editing the query in a search results page's own search box, leaving back as the only way out.
- Fixed URLs opened from bookmarks, history, offline pages, or a userscript install being reopened repeatedly after the app returns to the foreground.
- The toolbar preview on the "Toolbar customization" page is now drawn statically, so entering the page no longer stutters.

## 3.3.1 (1000445)

2026-09-21

This release rebuilds the tab overview as drag-open stacked cards, wires the bottom bar, middle bar, and address bar to matching gestures, and makes the Community update notice read the public release feed.

- The tab overview becomes stacked cards and is now the default shape; cards scale by layer, so the front-to-back order is clear at a glance.
- Dragging up from the bottom bar opens the tab overview; swiping up the middle bar does the same.
- Swiping the bottom address bar left or right switches tabs.
- Closing a stacked tab uses a real fill plus throw animation, with no layer flicker while cards deform.
- After closing one tab the whole stack can still be panned and does not get stuck.
- "Toolbar customization" chooses which panel the middle bar swipe opens: the tools panel or the tab manager.
- The sync result dialog lists name and status, and long names are no longer squeezed.
- Fixed the title not redrawing after switching segmented tabs.
- The Community update notice now announces from the public release feed.

## 3.2.3 (1000439)

2026-09-19

This release moves the heavy part of history sync to the background and reduces sync traffic, fixes WebDAV first sync failing on some NAS devices, makes cross-device link smoother on desktop, and unifies dialogs and naming.

- History sync reads local data and computes differences on a background thread, so the interface keeps up during sync; an unchanged sync is skipped, and deleting a few records no longer re-uploads the whole shard.
- Compatible with NAS devices such as fnOS that create a 0-byte file when locking: WebDAV first sync no longer fails, and previously left empty snapshot files are repaired automatically.
- Cross-device link adapts to desktop: it becomes an embedded settings panel, and "link guide" opens in place instead of as a full page.
- The desktop address bar gains a "cross-device tabs" entry, showing and opening pages being browsed on other computers.
- Fixed tapping "cross-device link" on the "Sync" page on desktop being switched back to "General".
- The Chrome, Edge, and Firefox icons in the link guide become the official ones.
- Naming is unified as "cross-device link / cross-device tabs / Aira-sync extension / private deployment / page push".
- Dialog buttons are unified to a vertical layout with the primary action on top; "Clear browsing data" becomes an immersive bottom panel on phones; desktop dialogs are no longer clipped by width limits.
- The bottom toolbar gesture guide prompts once per device instead of repeatedly.

## 3.2.2 (1000436)

2026-09-19

This release brings the scrolling immersion effect and fixes bottom toolbar touch handling and cold-start home page display.

- Scrolling a page down fades the top toolbar and adds a progressive blur for more immersive reading.
- Fixed the blank areas beside the capsule swallowing taps after the bottom toolbar collapses; it no longer hugs the bottom edge when collapsed either.
- Fixed a closed toolbar panel popping back up while the page scrolls.
- Fixed the home cover being stretched or jumping on a cold start, and a theme color flash when the home snapshot is handed over.
- Sync method names are unified as "WebDAV sync / private deployment".

## 3.2.1 (1000433)

2026-09-17

This release adds batch selection to the download list, moves the heavy part of sync to the background, and fixes userscript import, the search engine menu, and swipe-to-close tabs.

- The download list supports batch selection, managing several downloads at once.
- Importing a local userscript overwrites an installed script of the same name instead of leaving a duplicate entry.
- Secure DNS gains a strict mode switch, so an unavailable DoH no longer falls back to plaintext resolution.
- Fixed the app proxy quick switch bouncing and the search engine menu being pushed below the keyboard.
- The swipe-to-close threshold for tabs is now computed from the card width, making it easier to swipe away.
- WebDAV sync reduces repeated remote reads, bookmark write projection is computed in the background, and very large history records no longer abort on a size probe failure.
- Reading overhead for the home shortcut grid and the history list is reduced, cutting main-thread jank from heavy pages and automatic sync.

## 3.1.2 (1000426)

2026-09-15

This release moves bookmark sync recomputation to the background and fixes large screens, novel reading, and first-sync deletion.

- Bookmark snapshot building and merging move to a background TaskPool, so a large bookmark tree no longer blocks the interface.
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

- Bookmark sync keeps deletion records for less time, making sync noticeably faster once an account accumulates many deletions.
- Fixed bookmarks doubling on a first sync and deleted bookmarks being synced back.
- Fixed some pages failing to launch an app after misdetecting the system platform.
- Fixed the video assistant play/pause button not refreshing and the address bar paste row's background in dark mode.
- History is grouped by device, so a browser update or reinstall no longer adds duplicate entries, and a shortcut to open Aira history is added.
- The Community edition no longer shows an unusable account sign-in entry.

## 3.0.2 (1000410)

2026-09-11

This release straightens out extra backup and improves the interface material, settings home, and history editing.

- Extra backup uses WebDAV only and writes from this device, instead of being merged as a second sync source.
- The browser glass surface and the novel reading action bar blur the content behind them.
- Home shortcut tiles become opaque for smoother scrolling on low-end devices.
- Fixed settings home content being covered by the title bar.
- While editing history, "More" opens batch copy, bookmark, and share menus directly.

## 3.0.1 (1000408)

2026-09-10

This release upgrades bookmark sync to v4, rebuilds the bottom toolbar and interface material, and adopts a new icon language.

- Bookmark sync is upgraded to v4, making sync recovery and switching more stable.
- The bottom toolbar becomes a system-style panel with drag reordering and more responsive gestures.
- The glass material and scrolling behavior of the tab, home, and settings top bars are more stable.
- History becomes its own search page, and the custom home preview is easier to tap.
- The app icon becomes a new outline icon set, making settings and toolbar entries easier to tell apart.
- The Community and Official editions share one source tree; the Community edition does not include the official cloud or the HUAWEI ID.

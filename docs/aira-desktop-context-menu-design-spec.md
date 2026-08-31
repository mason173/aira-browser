# Aira Desktop Context Menu Design Specification

## Scope

This specification applies to pointer-triggered context menus in Aira desktop and large-screen layouts. Phone and touch long-press menus remain separate interaction surfaces and keep their existing presentation unless a phone-specific redesign is approved.

The reference native implementation is `BrowserDesktopContextMenu.ets`. Callers provide menu groups, labels, optional verified shortcuts, enabled state, and actions. Callers do not restyle the menu container or rows.

ArkWeb webpage context menus keep their coordinate-positioned `WebContextMenuOverlay` owner because the press target lives inside Web content. In desktop mode that overlay must consume the same shared geometry, typography, grouping, divider, and hover tokens; it must not create a second desktop visual standard.

## Geometry And Typography

| Property | Standard |
| --- | --- |
| Compact menu width | 188vp, for short command sets |
| Standard menu width | 216vp |
| Wide menu width | 248vp, only for menus with verified long labels |
| Menu outer radius | 18vp |
| Menu horizontal inset | 4vp |
| Menu vertical inset | 6vp |
| Item height | 44vp |
| Item hover radius | 10vp |
| Item horizontal padding | 10vp |
| Primary label | 14fp, 20vp line height, one line with ellipsis |
| Shortcut label | 12fp, 18vp line height, one line, trailing aligned |
| Label-to-shortcut gap | 12vp |
| Group divider | 0.5vp, 10vp start and end margins |
| Disabled content opacity | 0.38 |

All letter spacing is 0. Menu text and dividers use the active semantic theme tokens.

## Interaction Rules

- Enabled items use ArkUI `HoverEffect.Highlight` with the standard 10vp item radius.
- Disabled items use `HoverEffect.None`, cannot dispatch actions, and apply the standard disabled opacity.
- Do not keep parent or item-local hover state for a native system context menu. State-driven menu rebuilds can cause popup flicker while the pointer moves between rows.
- Coordinate-positioned ArkWeb menus also use native `HoverEffect.Highlight` in desktop mode. They must not write local hover state while the pointer moves between rows.
- Keep the menu width and row metrics stable across hover, disabled, and shortcut states.
- Apply the selected width tier as an explicit numeric width at the custom menu-item content boundary, subtracting the shared horizontal menu insets. Do not use `width('100%')` inside a custom native `MenuItem`; its intrinsic popup measurement is not constrained by the declared root `Menu.width()`.
- Use the 216vp standard width by default. The 188vp compact tier is for short command sets, including a short shortcut column; the 248vp wide tier requires verified long labels. Neither override is a global desktop-menu width.
- Destructive actions use normal text styling unless a separate semantic destructive role is introduced centrally.

## Keyboard Shortcuts

- Show a shortcut only when the application implements that exact command for the same action.
- Place shortcuts at the trailing edge of the row using the shared shortcut typography.
- Do not invent conventional shortcuts. For example, a menu that restores one selected recently-closed record must not show the global restore-latest shortcut.
- Use the same human-readable notation as the desktop keyboard command owner, such as `Ctrl + R` and `Ctrl + W`.

## Grouping

- Use `MenuItemGroup` for semantic clusters and let the shared menu render dividers.
- Keep immediate navigation/open actions first, related edit/copy actions together, destructive removal actions in a later group, and settings or management navigation last.
- Do not place dividers manually inside callers.

## Ownership And Usage

- `BrowserDesktopMenuPresentationTokens.ets` owns the numeric design tokens.
- `BrowserDesktopContextMenu.ets` owns the ArkUI menu container, rows, typography, hover, disabled state, dividers, theme binding, and shortcut alignment.
- `WebContextMenuOverlayCoordinator.ets` owns ArkWeb menu placement and resolves the desktop width before the first frame; `WebContextMenuOverlay.ets` renders the shared desktop tokens without changing ArkWeb triggering or positioning.
- Feature components own action availability, labels, grouping, and dispatch only.
- New desktop right-click menus must use the shared module. Per-caller widths, radii, row heights, text sizes, raw colors, and custom hover state are not allowed.

Current standardized desktop surfaces are:

- Large-screen tab strip
- Home shortcuts/favorites
- Home recently-closed records
- Bookmark workspace records
- History site groups
- History timeline records
- ArkWeb webpage links, images, and userscript commands

Controlled touch and phone long-press menus remain outside this pointer-specific standard.

The current large-screen tab and recently-closed menus use the compact tier. Home, bookmarks, history timeline, and ArkWeb webpage menus use the standard tier. History site groups use the wide tier because their longest command is a full descriptive sentence.

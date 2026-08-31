# Gravity UI bottom toolbar candidates

This directory contains the Gravity UI SVG candidates selected for Aira's complete browser bottom-toolbar system.

- Source collection: [Gravity UI Icons](https://icon-sets.iconify.design/gravity-ui/)
- Upstream version: `2.20.0`
- Upstream project: [gravity-ui/icons](https://github.com/gravity-ui/icons)
- License: MIT; see [`../LICENSE`](../LICENSE)
- Download source: Iconify public SVG API
- Status: source candidates only; not integrated into Aira resources or the generated operational icon font
- Aira icon mappings: 49
- Unique downloaded Gravity UI SVGs: 46

## Scope

The inventory covers:

- the compact address-bar chrome and its editing states;
- expanded and customizable web/home toolbar actions;
- reader, offline-page, viewer, and tabs-surface actions;
- the tabs-overview bottom chrome.

The complete one-to-one mapping is stored in [`mapping.csv`](mapping.csv). Some Aira icon IDs intentionally share a Gravity UI asset where the visual meaning is identical, such as search, share, and palette/theme actions.

The more interpretive choices are:

- tabs: `layout-tabs`;
- translation: `letter-group`;
- text size: `magnifier-plus` and `magnifier-minus`;
- screen orientation: `arrows-3-rotate-right`;
- private mode: `eye-slash`.

The current toolbar implementation remains unchanged. Any later integration must follow the Aira operational icon catalog and font-generation workflow instead of copying these SVGs directly into HarmonyOS generated media resources.

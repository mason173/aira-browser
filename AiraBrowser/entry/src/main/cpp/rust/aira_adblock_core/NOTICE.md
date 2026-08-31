# adblock-rust Notice

This wrapper links `adblock` version `0.13.2`, developed by Brave Software and contributors and licensed under the
Mozilla Public License 2.0.

- Upstream source: https://github.com/brave/adblock-rust
- Packaged upstream tag commit: `00b19a06508ddd4f3453779f8618983421ddf32b`
- Packaged crate source: https://crates.io/crates/adblock/0.13.2
- License: https://www.mozilla.org/MPL/2.0/

The exact resolved dependency graph is recorded in `Cargo.lock`. A copy of the MPL-2.0 license is included in the HAP
as `adblock-rust-LICENSE.txt`. The complete Rust dependency license inventory generated from that lock file is included
as `adblock-rust-THIRD-PARTY-LICENSES.txt`.

The engine also embeds the Brave redirect resource snapshot from the same tag. Its exact source and hash are recorded in
`resources/SOURCE.md`. Distribution notices are packaged as `adblock-redirect-resources-NOTICE.txt` and
`adblock-redirect-resources-GPL-3.0.txt`; the existing `adblock-rust-LICENSE.txt` supplies the MPL-2.0 text.

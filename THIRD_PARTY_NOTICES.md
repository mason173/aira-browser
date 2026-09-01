# Third-Party Notices

The root `LICENSE` covers Aira-authored source code unless a file or directory states different terms. Third-party
components retain their own licenses and notices.

## Included Source And Generated Runtime Components

- **curl 8.7.1** is distributed under the curl license. The license is at
  `AiraBrowser/entry/src/main/cpp/third_party/curl/COPYING`.
- **Mbed TLS 3.6.2** is available under Apache-2.0 OR GPL-2.0-or-later. The bundled license text is at
  `AiraBrowser/entry/src/main/cpp/third_party/mbedtls/LICENSE`.
- **Mozilla Readability 0.6.0** is distributed under Apache-2.0. Source provenance and license are under
  `third_party/mozilla-readability/`.
- **adblock-rust 0.13.2** is distributed under MPL-2.0. Its pinned source, transitive dependency inventory, redirect
  resource notice, and packaged license texts are described in
  `AiraBrowser/entry/src/main/cpp/rust/aira_adblock_core/NOTICE.md`.
- **Gravity UI 2.20.0 icons** are distributed under MIT. The license is at
  `resources/icon-sources/aira/vendor/gravity-ui/2.20.0/LICENSE`.
- **Lucide 1.38.0 SVGs and the Aira Operational Icon font** are distributed under ISC. The generated font keeps Aira's
  existing semantic IDs and code points for runtime compatibility while its source manifest and SVGs are vendored under
  the Lucide source tree. The license is at
  `resources/icon-sources/aira/vendor/lucide/review-2026-09/LICENSE`.
- HarmonyOS and AGConnect packages are declared in `AiraBrowser/oh-package.json5` and remain subject to their publishers'
  terms.
- Aira-sync JavaScript dependencies and WebDAV provider-branding notes are documented in
  `extensions/aira-sync/THIRD_PARTY_NOTICES.md`.
- Personal Server runtime dependencies are documented in `services/personal-server/THIRD_PARTY_NOTICES.md`.

## Icon Compatibility Metadata

The Aira icon catalog preserves its historical app resource family names, semantic IDs, and code-point mapping so
existing ArkTS consumers and packaged font loading remain stable. The source SVGs and generated font are the Lucide-based
set described above and are distributed under the applicable Lucide/Feather notices.

This notice is informational and does not replace any third-party license text.

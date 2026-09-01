# Aira HarmonyOS Project

This is the HarmonyOS NEXT ArkTS project for Aira.

## Node version

This repository should use Node.js 18.x LTS at the repo root. The root `.nvmrc` and `.node-version` are pinned to
`18.20.8` so version managers can switch automatically.

For HarmonyOS builds, `./scripts/build-aira-browser.sh` uses DevEco Studio's bundled Node runtime.

## Project Structure

The project is organized around these module boundaries:

- `app/`: ability entry, bootstrap wiring, route constants, top-level pages
- `core/`: browser shell, navigation, tab manager, Web runtime wrapper
- `features/`: new tab, search, shortcuts, bookmarks, history, settings, sync
- `data/`: preferences, database plan, repositories
- `services/`: sync, download, media, search, settings, and browser services
- `common/`: constants, shared models, URL utilities

The main browser shell is `entry/src/main/ets/app/pages/BrowserShellPage.ets`.

To build this demo reliably, use the helper script from the repository root:

```bash
./scripts/build-aira-browser.sh
```

The script builds the `AiraBrowser` project in place, configures DevEco Studio's bundled SDK/JBR, validates that the signing profile matches the effective bundle name, and outputs a signed HAP. Machine-local signing lives in `AiraBrowser/build-profile.local.json5`, which is ignored by git.

The native Rust build automatically uses the persistent user-owned cache `~/.cache/aira-browser-cargo-home` when the default `~/.cargo/registry` is not writable, so dependencies are downloaded once and reused across builds. Repairing the default cache is optional: `sudo chown -R "$(whoami)":staff ~/.cargo/registry`.

The ad-block native authority module also requires `rustup` to be available on `PATH`. Its CMake build pins Rust `1.97.1`,
installs the required OHOS target through `rustup`, and uses DevEco's Native SDK linker/sysroot. Set
`AIRA_RUSTUP_EXECUTABLE=/absolute/path/to/rustup` only when `rustup` is intentionally installed outside `PATH`.

When `Cargo.lock` changes, regenerate the packaged Rust dependency notices with:

```bash
cargo install cargo-about --locked --version 0.9.1 --features cli
cargo about generate \
  --manifest-path AiraBrowser/entry/src/main/cpp/rust/aira_adblock_core/Cargo.toml \
  --config AiraBrowser/entry/src/main/cpp/rust/aira_adblock_core/about.toml \
  --target aarch64-unknown-linux-ohos \
  --locked \
  --fail \
  --output-file AiraBrowser/entry/src/main/resources/rawfile/adblock-rust-THIRD-PARTY-LICENSES.txt \
  AiraBrowser/entry/src/main/cpp/rust/aira_adblock_core/about.hbs
```

For a one-off build with another DevEco-generated profile, set `AIRA_BUILD_PROFILE=/abs/path/to/build-profile.json5`. Do not commit encrypted password fields or absolute signing-material paths.

The source tree supports two distributions. They use the same commit and differ only in build-time identity and
capability inputs:

- Community (default source identity): `org.aira.browser` / `Aira`
- Official (private production identity): `com.aira.browser` / `Aira`

Select the distribution independently from the debug/release build variant with `AIRA_DISTRIBUTION=community|official`.
Community is the public-safe choice and does not include Aira's AGConnect project, Huawei Account/Space approvals, IAP,
or hosted Aira Cloud access. WebDAV and the single-owner Personal Server Provider remain available; Personal Server can
also connect Aira-sync for Page Push and Cross-device Tabs without Aira Account or Pro. A Community Huawei
build may provide the builder's own Huawei project only through separate configuration and approval; it never inherits
Aira's production identity.

The minimum supported HarmonyOS API is 23. The tracked and local build profiles must set both
`compatibleSdkVersion` and `targetSdkVersion` to `6.1.0(23)` or newer; the build script rejects lower or unparseable
profiles before invoking Hvigor. API 22 devices are therefore excluded by the package's `minAPIVersion` metadata.

The build script has two variants:

- Default: `./scripts/build-aira-browser.sh`
- Release: `AIRA_BUILD_VARIANT=release SKIP_INSTALL=1 ./scripts/build-aira-browser.sh`

Default builds keep debug routes and source maps in the HAP, and keep the source `AppScope/app.json5` version.

Release uses `buildMode=release`, removes source maps from the HAP, and temporarily prunes diagnostics/test-lab packaging inputs before restoring source files after the build exits. The selected distribution identity is restored after the build exits. The release version name is derived from the source version by removing preview suffixes such as `-dev`, `-preview`, `-alpha`, `-beta`, or `-rc`; the release version code reuses the source `versionCode` by default.

Version overrides are also build-time only and are restored after the script exits:

- `AIRA_RELEASE_VERSION_NAME=0.1.0` overrides only release builds
- `AIRA_RELEASE_VERSION_CODE=1000001` overrides only release builds
- `AIRA_VERSION_NAME=0.1.0-hotfix.1` overrides both default and release builds
- `AIRA_VERSION_CODE=1000002` overrides both default and release builds

Example release build with explicit version metadata:

```bash
AIRA_BUILD_VARIANT=release \
AIRA_RELEASE_VERSION_NAME=0.1.0 \
AIRA_RELEASE_VERSION_CODE=1000001 \
SKIP_INSTALL=1 \
./scripts/build-aira-browser.sh
```

Because HarmonyOS signing profiles are tied to the bundle name, use a profile matching the selected distribution. Official
profiles must match `com.aira.browser`; Community profiles must match `org.aira.browser`.

Official builds also require private Huawei inputs. Keep them outside Git and provide either `AIRA_AGCONNECT_CONFIG`
pointing to the private `agconnect-services.json`, or place that file at `AiraBrowser/agconnect-services.local.json`.
The script reads `app_id` and `client_id` from that private file unless `AIRA_HUAWEI_APP_ID` and
`AIRA_HUAWEI_CLIENT_ID` are supplied explicitly. The AGConnect file is copied into the package only for the duration of
the build and removed during cleanup.

Examples:

```bash
# Public-safe Community build (requires a Community signing profile)
AIRA_DISTRIBUTION=community SKIP_INSTALL=1 ./scripts/build-aira-browser.sh

# Public CI/audit build (unsigned and not installable)
AIRA_DISTRIBUTION=community AIRA_ALLOW_UNSIGNED_BUILD=1 SKIP_INSTALL=1 ./scripts/build-aira-browser.sh

# Private Official build (requires private AGConnect and Official signing inputs)
AIRA_DISTRIBUTION=official SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

## Signing

Default installs use the fixed AppGallery debug signing config:

```bash
./scripts/install-aira-browser.sh
```

Both debug and release signing configs are generated into the ignored local build profile. Keep the signing files together on each machine, preferably in `~/AiraSigning`:

- `debug/aira-debug-keystore.p12`
- `debug/aira-debug-certificate.cer`
- `debug/aira-debug-profile.p7b`
- `debug/aira-debug-request.csr`
- `debug/material/`
- `release/aira-release-keystore.p12`
- `release/aira-release-certificate.cer`
- `release/aira-release-profile.p7b`
- `release/aira-release-request.csr`
- `release/material/`

Then generate the local build profile:

```bash
AIRA_SIGNING_STORE_PASSWORD='...' ./scripts/setup-aira-signing.sh
```

If debug and release use different p12 passwords, pass `AIRA_DEBUG_STORE_PASSWORD='...'` and `AIRA_RELEASE_STORE_PASSWORD='...'` separately. If a key password differs from its p12 store password, also pass `AIRA_DEBUG_KEY_PASSWORD='...'` or `AIRA_RELEASE_KEY_PASSWORD='...'`. If the files are not in `~/AiraSigning`, pass `AIRA_SIGNING_DIR=/abs/path` or the individual `AIRA_DEBUG_*` and `AIRA_RELEASE_*` path overrides shown by `./scripts/setup-aira-signing.sh --help`.

The setup script verifies the debug Profile is an AppGallery `debug` Profile and the release Profile is an AppGallery `release` Profile for the selected bundle name, auto-detects the p12 aliases, encrypts passwords for each local HarmonyOS signing `material/`, and writes the ignored `AiraBrowser/build-profile.local.json5`. Set `AIRA_DISTRIBUTION=community` while running it to prepare a Community signing profile.

Build a store `.app` package with:

```bash
AIRA_BUILD_VARIANT=release AIRA_BUILD_PACKAGE_FORMAT=app SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

To create a dedicated translation worktree, run this from the main repository:

```bash
./scripts/create-aira-worktree.sh
```

By default it creates a sibling `aira-browser-translation` worktree on branch `codex/translation-worktree` and preserves
the shared app identity:

- Bundle name: `com.aira.browser`
- App name: `Aira`

After creating the worktree, copy or regenerate `AiraBrowser/build-profile.local.json5` with `./scripts/setup-aira-signing.sh` if release packaging is needed there.

## Running on a real device

Open the repository's `AiraBrowser/` directory in DevEco Studio.

For command-line builds across different computers, copy the signing files to the local signing directory and run `./scripts/setup-aira-signing.sh` once per machine, then use the repo script.

To install directly to a connected phone:

```bash
./scripts/install-aira-browser.sh
```

- One connected phone: auto-install.
- Multiple phones: `HDC_TARGET=<device-id> ./scripts/install-aira-browser.sh`
- Build only (skip install): `SKIP_INSTALL=1 ./scripts/build-aira-browser.sh`

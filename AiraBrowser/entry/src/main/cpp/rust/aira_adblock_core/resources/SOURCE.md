# Brave redirect resource snapshot

- Source repository: <https://github.com/brave/adblock-rust>
- Tag: `v0.13.2`
- Commit: `00b19a06508ddd4f3453779f8618983421ddf32b`
- Upstream path: `data/brave/brave-resources.json`
- SHA-256: `de6eb441a4ba2823d2cc67beabae0a3e0b6862cc56ca8586af6bac654c45f3fd`

The JSON is kept byte-for-byte identical to the upstream snapshot. While constructing the Rust engine, Aira adds ABP
blank-resource aliases and normalizes the AdGuard legacy `no-window-open-if, 0|1, pattern` arguments to the equivalent
Brave/uBO pattern form; it does not modify this source asset.

The upstream repository is licensed under MPL-2.0. Some resource bodies retain their own uBlock Origin GPL-3.0 notices.
The HAP includes the MPL-2.0 and GPL-3.0 texts plus a resource notice pointing to the exact source above.

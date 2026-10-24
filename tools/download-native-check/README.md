# Native download regression checks

Run `./scripts/check-download-native.sh` from the repository root. It compiles the
production download core and HLS parser/decryptor, starts a loopback HTTP server,
and asserts downloaded bytes and failure states. No device is required.

Dependencies: a C/C++17 compiler, Python 3, OpenSSL CLI, and libcurl development
headers/library (curl 7.85+). macOS uses the selected Xcode SDK; Linux CI can install
`libcurl4-openssl-dev`. AES uses this repository's vendored Mbed TLS source with a
minimal host configuration. Independent OpenSSL encryption produces the fixtures.
The proxy regression script uses the same host compiler helper.

The cases cover HTTP redirects and Cookie replacement, interrupted downloads with
strong ETag/If-Range validation, safe restart without a validator, redirected HLS
manifests, Cookie propagation to keys and segments, ordered initialization sections,
byte ranges, AES-128 CBC with explicit and media-sequence IVs, key rotation,
METHOD=NONE, encrypted initialization sections, streaming PKCS#7 removal, and
malformed key/IV/padding/range rejection. External audio renditions, SAMPLE-AES,
non-identity DRM key formats, and encrypted initialization sections without an
explicit IV fail explicitly instead of producing an incomplete file.

Protocol references:

- [RFC 8216](https://www.rfc-editor.org/rfc/rfc8216.html): sections 4.3.2.2,
  4.3.2.4, 4.3.2.5, 4.3.4.2, and 5.2.
- [libcurl Cookie engine](https://curl.se/libcurl/c/CURLOPT_COOKIEFILE.html),
  [Cookie import](https://curl.se/libcurl/c/CURLOPT_COOKIELIST.html), and
  [cross-thread sharing limits](https://curl.se/libcurl/c/CURLSHOPT_SHARE.html).
- [Mbed TLS AES CBC](https://mbed-tls.readthedocs.io/projects/api/en/v3.6.5/api/file/aes_8h/).

These are host transport tests. HarmonyOS TLS/system-certificate integration and
playback of real media remain separate build/device checks. HLS live playlists and
separate audio/video muxing are not implemented. Initialization-section byte ranges
require an explicit offset; media byte ranges support the RFC's implicit offset
when the immediately preceding segment uses the same resource.

# Mozilla Readability

- Upstream: https://github.com/mozilla/readability
- Package: `@mozilla/readability@0.6.0`
- Package integrity: `sha512-juG5VWh4qAivzTAeMzvY9xs9HY5rAcr2E4I7tiSSCokRFi7XIZCAu92ZkSTsIj1OPceCifL3cpfteP3pDT9/QQ==`
- License: Apache-2.0; see `LICENSE.md` in this directory.

`tools/reader-extraction-spike/generate-runtime.mjs` bundles and minifies the package's exported `Readability` class into
the generated ArkTS string `ReaderReadabilityRuntimeSource.ets`. The upstream algorithm is not modified. Aira wraps it
with project-owned DOM pre-cleaning, site-adapter precedence, result validation, typed-block conversion, diagnostics,
and fallback behavior outside the generated bundle.

Regenerate from the repository root with:

```bash
cd tools/reader-extraction-spike
npm ci
npm run generate-runtime
```

# Reader Extraction Spike

This tool compares Mozilla Readability 0.6.0 and Aira's integrated production extractor against the exact
pre-integration `ReaderExtractionService.ets` from commit `cc1ea924`. It runs in a fresh headless local Chrome process
and never captures screenshots, video, display output, accessibility trees, or layout dumps.

## Run

```bash
cd tools/reader-extraction-spike
npm ci
npm run run
```

Results are written to the ignored `.tmp/reader-extraction-spike/` directory at the repository root. The default run
uses deterministic labelled fixtures and a small public live-page smoke corpus. Use `npm run fixtures` when network
access is unavailable.

The harness reads the baseline service directly from Git and bundles both service versions at runtime instead of
maintaining a second algorithm copy. It pins the baseline commit, Readability, and every harness dependency.

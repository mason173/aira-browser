#!/usr/bin/env node
'use strict';

// Compatibility entrypoint for the old download-only harness.
// The download fixture now lives inside the unified manual navigation lab.
if (process.argv[2] && !process.env.PORT) {
  process.env.PORT = process.argv[2];
}

require('../tools/manual-navigation-lab/server.js');

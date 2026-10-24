#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/aira-download-native.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
"$root/tools/download-native-check/build-host.sh" "$work" "$root/tools/download-native-check/download_native_host_test.cpp"
python3 "$root/tools/download-native-check/native_lab.py" "$work/download_host_test" "$work"

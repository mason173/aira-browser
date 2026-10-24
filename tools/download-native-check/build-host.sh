#!/bin/sh
# Build the actual download core against host curl. Crypto uses the vendored
# Mbed TLS AES implementation; only unrelated crypto features are disabled.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
work=$1
driver=$2
cpp="$root/AiraBrowser/entry/src/main/cpp"
if [ "$(uname -s)" = Darwin ]; then
  sdk="${AIRA_DOWNLOAD_PROXY_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
  export SDKROOT="$sdk"
fi
for source in aes platform_util; do
  "${CC:-cc}" -c -O2 -I"$cpp/third_party/mbedtls/include" -I"$root/tools/download-native-check" \
    '-DMBEDTLS_CONFIG_FILE="host_mbedtls_config.h"' \
    "$cpp/third_party/mbedtls/library/$source.c" -o "$work/$source.o"
done
"${CXX:-c++}" -std=c++17 -pthread -I"$cpp" -I"$cpp/third_party/mbedtls/include" \
  -I"$root/tools/download-native-check" '-DMBEDTLS_CONFIG_FILE="host_mbedtls_config.h"' \
  "$cpp/download_core.cpp" "$cpp/download_hls.cpp" "$driver" \
  "$work/aes.o" "$work/platform_util.o" -lcurl -o "$work/download_host_test"

#!/bin/sh

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
application_dir="$repository_dir/AiraBrowser"
result_file="$application_dir/entry/.test/default/intermediates/test/coverage_data/test_result.txt"
deveco_root=${DEVECO_STUDIO_HOME:-/Applications/DevEco-Studio.app/Contents}
node_binary="$deveco_root/tools/node/bin/node"
hvigor_entry="$deveco_root/tools/hvigor/bin/hvigorw.js"

if [ ! -x "$node_binary" ] || [ ! -f "$hvigor_entry" ]; then
  echo "DevEco Studio command-line runtime was not found under: $deveco_root" >&2
  exit 2
fi

export DEVECO_SDK_HOME=${AIRA_DEVECO_SDK_HOME:-"$deveco_root/sdk"}
export JAVA_HOME=${AIRA_JAVA_HOME:-"$deveco_root/jbr/Contents/Home"}
export PATH="$JAVA_HOME/bin:$PATH"

rm -f "$result_file"
cd "$application_dir"

"$node_binary" "$hvigor_entry" clean --no-daemon
clean_code=$?
if [ "$clean_code" -ne 0 ]; then
  exit "$clean_code"
fi

"$node_binary" "$hvigor_entry" test -p module=entry -p coverage=false --no-daemon
hvigor_code=$?
if [ "$hvigor_code" -ne 0 ]; then
  exit "$hvigor_code"
fi

if [ ! -f "$result_file" ]; then
  echo "Local Test did not produce the expected Hypium result: $result_file" >&2
  exit 1
fi

summary=$(tail -n 1 "$result_file")
echo "$summary"

if grep -Eq '^result=(Failure|Error)$' "$result_file"; then
  echo "Hypium reported failed or errored cases even though Hvigor returned success." >&2
  grep -E '^(class|test|result)=' "$result_file" | tail -n 80 >&2
  exit 1
fi

if ! echo "$summary" | grep -Eq '^Tests run: [0-9]+, Failure: 0, Error: 0, Pass: [0-9]+, Ignore: [0-9]+$'; then
  echo "Hypium summary is missing or not green." >&2
  exit 1
fi

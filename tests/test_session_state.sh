#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc SessionState.swift tests/SessionStateTests.swift -o "$test_dir/session-tests"
"$test_dir/session-tests"

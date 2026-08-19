#!/bin/bash

if [ "${0##*/}" = ps ]; then
    cat <<'EOF'
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
alice      101  1.0  0.1 100000  1000 ?        S    10:00   0:01 python train.py --job alpha
alice      102  0.0  0.1 100000  1000 ?        Z    10:00   0:00 python zombie.py
bob        103  2.0  0.2 200000  2000 ?        R    10:01   0:02 worker --target python
alice      104  1.5  0.2 200000  2000 ?        R    10:02   0:03 bash python helper.py
root       105  0.0  0.1 100000  1000 ?        D    10:03   0:00 python root_job.py
EOF
    exit 0
fi

set -u

test_root=$(cd "$(dirname "$0")/.." && pwd)
px_script="$test_root/.shrc_scripts/px.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT

ln -s "$test_root/tests/test_px.sh" "$test_tmp/ps"
export PATH="$test_tmp:$PATH"
export USER=alice

tests=0
failures=0

pass()
{
    local label="$1"
    tests=$((tests + 1))
    printf 'ok %d - %s\n' "$tests" "$label"
}

fail()
{
    local label="$1"
    local detail="$2"
    tests=$((tests + 1))
    failures=$((failures + 1))
    printf 'not ok %d - %s\n' "$tests" "$label"
    printf '  %s\n' "$detail"
}

assert_contains()
{
    local haystack="$1"
    local needle="$2"
    local label="$3"

    case "$haystack" in
        *"$needle"*) pass "$label" ;;
        *) fail "$label" "missing: <$needle>" ;;
    esac
}

assert_not_contains()
{
    local haystack="$1"
    local needle="$2"
    local label="$3"

    case "$haystack" in
        *"$needle"*) fail "$label" "unexpected: <$needle>" ;;
        *) pass "$label" ;;
    esac
}

run_px()
{
    bash "$px_script" "$@"
}

output=$(run_px l python)
status=$?
[ "$status" -eq 0 ] && pass 'command-prefix filter succeeds' \
    || fail 'command-prefix filter succeeds' "status: $status"
assert_contains "$output" 'USER       PID' 'header is preserved'
assert_contains "$output" '101' 'l includes an active command-prefix match'
assert_not_contains "$output" '102' 'l excludes zombie state'
assert_not_contains "$output" '103' 'l does not match only in arguments'
assert_not_contains "$output" '104' 'l does not match a different command name'

output=$(run_px la python)
assert_contains "$output" '101' 'la includes command match'
assert_contains "$output" '103' 'la includes full-argument match'
assert_contains "$output" '104' 'la includes later argument match'
assert_not_contains "$output" '102' 'la still excludes zombie state'

output=$(run_px -ui la python)
assert_contains "$output" '101' '-ui includes current user'
assert_contains "$output" '104' '-ui keeps current-user argument match'
assert_not_contains "$output" '103' '-ui excludes another user'
assert_not_contains "$output" '105' '-ui excludes root'

output=$(run_px r python)
assert_contains "$output" 'USER       PID' 'empty match set still prints header'
assert_not_contains "$output" '101' 'r excludes sleeping process'
assert_not_contains "$output" '105' 'r excludes uninterruptible process'

plain_output=$(run_px l python)
assert_not_contains "$plain_output" $'\033[' 'redirected output contains no ANSI color'

if command -v script >/dev/null 2>&1; then
    color_output=$(GREP_COLORS='ms=01;35' TERM=xterm \
        script -qec "bash '$px_script' l python" /dev/null)
    color_output=${color_output//$'\r'/}
    assert_contains "$color_output" $'\033[01;35m' 'terminal output enables grep match color'
    assert_contains "$color_output" 'python' 'colored terminal output keeps matched text'
else
    fail 'terminal output enables grep match color' 'script command is unavailable'
fi

if grep -Fxq 'px' "$test_root/.shrc_scripts/manifest.txt"; then
    pass 'px is present in the Unix tool manifest'
else
    fail 'px is present in the Unix tool manifest' 'manifest entry is missing'
fi

if grep -Fq 'shrc run px "$@"' "$test_root/.shrc"; then
    pass '.shrc keeps a thin px wrapper'
else
    fail '.shrc keeps a thin px wrapper' 'wrapper call is missing'
fi

printf '1..%d\n' "$tests"
if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

#!/bin/bash

if [ "${0##*/}" = ps ]; then
    cat <<'EOF'
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
alice      101  1.0  0.1 100000  1000 ?        S    10:00   0:01 /usr/bin/python train.py --job alpha
alice      102  0.0  0.1 100000  1000 ?        Z    10:00   0:00 /usr/bin/python zombie.py
bob        103  2.0  0.2 200000  2000 ?        R    10:01   0:02 worker --target python
alice      104  1.5  0.2 200000  2000 ?        R    10:02   0:03 bash python helper.py
root       105  0.0  0.1 100000  1000 ?        D    10:03   0:00 /usr/bin/python root_job.py
alice      106  1.2  0.2 200000  2000 ?        R    10:04   0:02 /opt/venv/bin/python3 serve.py
bob        107  0.8  0.2 200000  2000 ?        R    10:05   0:01 /srv/runtime/python worker.py
alice      108  0.3  0.1 100000  1000 ?        S    10:06   0:00 /usr/local/bin/notpython --runner python
alice      109  0.4  0.1 100000  1000 ?        S    10:07   0:00 /opt/codex/bin/codex agent
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
assert_contains "$output" '101' 'l matches a program basename after /usr/bin'
assert_contains "$output" '106' 'l keeps prefix matching on a path basename'
assert_contains "$output" '107' 'l basename matching applies to every user'
assert_not_contains "$output" '102' 'l excludes zombie state'
assert_not_contains "$output" '103' 'l does not match only in arguments'
assert_not_contains "$output" '104' 'l does not match a different command name'
assert_not_contains "$output" '108' 'l anchors the pattern at the basename start'

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

output=$(run_px -ui l python)
assert_contains "$output" '101' 'pxil matches a current-user path basename'
assert_contains "$output" '106' 'pxil matches a prefixed current-user basename'
assert_not_contains "$output" '107' 'pxil excludes another user path match'
assert_not_contains "$output" '108' 'pxil does not search later basename text'

output=$(run_px r python)
assert_contains "$output" 'USER       PID' 'pxr preserves the header'
assert_contains "$output" '106' 'pxr matches a running path basename'
assert_contains "$output" '107' 'pxr matches another user running basename'
assert_not_contains "$output" '101' 'r excludes sleeping process'
assert_not_contains "$output" '105' 'r excludes uninterruptible process'

output=$(run_px -ui r python)
assert_contains "$output" '106' 'pxir matches a current-user running basename'
assert_not_contains "$output" '107' 'pxir excludes another user running basename'

plain_output=$(run_px l python)
assert_not_contains "$plain_output" $'\033[' 'redirected output contains no ANSI color'

if command -v script >/dev/null 2>&1; then
    color_output=$(GREP_COLORS='ms=01;35' TERM=xterm \
        script -qec "bash '$px_script' l python" /dev/null)
    color_output=${color_output//$'\r'/}
    assert_contains "$color_output" $'\033[01;35m' 'terminal output enables grep match color'
    assert_contains "$color_output" 'python' 'colored terminal output keeps matched text'

    color_output=$(GREP_COLORS='ms=01;35' TERM=xterm \
        script -qec "bash '$px_script' l codex" /dev/null)
    color_output=${color_output//$'\r'/}
    colored_codex=$'\033[01;35m\033[Kcodex\033[m\033[K'
    assert_contains "$color_output" "/opt/codex/bin/${colored_codex}" \
        'pxl colors only the matched program basename'
    assert_not_contains "$color_output" "/opt/"$'\033[01;35m\033[Kcodex' \
        'pxl leaves matching directory names uncolored'
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

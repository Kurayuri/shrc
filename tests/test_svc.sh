#!/bin/bash

if [ "${0##*/}" = systemctl ]; then
    scope=system
    list_unit_files=0
    unit=""

    for arg in "$@"; do
        case "$arg" in
            --user) scope=user ;;
            list-unit-files) list_unit_files=1 ;;
        esac
        unit="$arg"
    done

    if [ "$list_unit_files" -eq 1 ]; then
        if [ "$scope" = user ]; then
            units=" ${SVC_TEST_USER_UNITS:-} "
        else
            units=" ${SVC_TEST_SYSTEM_UNITS:-} "
        fi

        case "$units" in
            *" $unit "*) printf '%s enabled enabled\n' "$unit"; exit 0 ;;
            *) exit 1 ;;
        esac
    fi

    printf '%s\n' "$*" >> "$SVC_TEST_LOG"
    exit 0
fi

set -u

test_root=$(cd "$(dirname "$0")/.." && pwd)
svc_script="$test_root/.shrc_scripts/svc.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT

ln -s "$test_root/tests/test_svc.sh" "$test_tmp/systemctl"
export PATH="$test_tmp:$PATH"
export SVC_TEST_LOG="$test_tmp/actions.log"

tests=0
failures=0

assert_equal()
{
    local expected="$1"
    local actual="$2"
    local label="$3"
    tests=$((tests + 1))

    if [ "$actual" != "$expected" ]; then
        printf 'not ok %d - %s\n' "$tests" "$label"
        printf '  expected: <%s>\n' "$expected"
        printf '  actual:   <%s>\n' "$actual"
        failures=$((failures + 1))
    else
        printf 'ok %d - %s\n' "$tests" "$label"
    fi
}

run_svc()
{
    export SVC_TEST_SYSTEM_UNITS="$1"
    export SVC_TEST_USER_UNITS="$2"
    shift 2
    bash "$svc_script" "$@"
}

last_action()
{
    if [ -s "$SVC_TEST_LOG" ]; then
        command tail -n 1 "$SVC_TEST_LOG"
    fi
}

reset_log()
{
    : > "$SVC_TEST_LOG"
}

reset_log
output=$(run_svc 'alpha.service' '' sa alpha --no-block 2>&1)
status=$?
assert_equal 0 "$status" 'system-only service succeeds'
assert_equal 'start alpha --no-block' "$(last_action)" 'system-only service uses system manager'
assert_equal '' "$output" 'system-only service is silent'

reset_log
output=$(run_svc '' 'beta.service' sp beta.service 2>&1)
status=$?
assert_equal 0 "$status" 'user-only service succeeds'
assert_equal '--user stop beta.service' "$(last_action)" 'user-only service adds --user'
assert_equal '' "$output" 'user-only service is silent'

reset_log
output=$(run_svc 'shared.service' 'shared.service' rs shared 2>&1)
status=$?
assert_equal 0 "$status" 'service in both scopes succeeds'
assert_equal 'restart shared' "$(last_action)" 'service in both scopes prefers system manager'
assert_equal "svc: 'shared' exists in both system and user scopes; using system scope" \
    "$output" 'service in both scopes prints a notice'

reset_log
output=$(run_svc '' '' av missing 2>&1)
status=$?
assert_equal 1 "$status" 'missing service fails'
assert_equal '' "$(last_action)" 'missing service runs no action'
assert_equal 'svc: service not found in system or user scope: missing' \
    "$output" 'missing service explains the failure'

reset_log
output=$(run_svc '' 'worker@.service' p worker@7 --lines=10 2>&1)
status=$?
assert_equal 0 "$status" 'user template instance succeeds'
assert_equal '--user status --no-pager worker@7 --lines=10' "$(last_action)" \
    'template instance selects user manager and keeps original name'
assert_equal '' "$output" 'template instance is silent'

for action_case in 'av enable' 'dv disable' 'rl reload'; do
    set -- $action_case
    reset_log
    output=$(run_svc 'alpha.service' '' "$1" alpha 2>&1)
    status=$?
    assert_equal 0 "$status" "$1 action succeeds"
    assert_equal "$2 alpha" "$(last_action)" "$1 action uses resolved scope"
    assert_equal '' "$output" "$1 action is silent"
done

reset_log
output=$(run_svc '' '' pu explicit.service 2>&1)
status=$?
assert_equal 0 "$status" 'explicit user status remains available'
assert_equal 'status --no-pager --user explicit.service' "$(last_action)" \
    'explicit user status bypasses automatic resolution'

printf '1..%d\n' "$tests"
if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

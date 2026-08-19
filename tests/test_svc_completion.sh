#!/bin/bash

if [ "${0##*/}" = systemctl ]; then
    scope=system

    for arg in "$@"; do
        [ "$arg" = --user ] && scope=user
    done

    if [ "$scope" = user ]; then
        units="${SVC_TEST_USER_UNITS:-}"
    else
        units="${SVC_TEST_SYSTEM_UNITS:-}"
    fi

    for unit in $units; do
        printf '%s enabled enabled\n' "$unit"
    done
    exit 0
fi

set -u
export LC_ALL=C

test_root=$(cd "$(dirname "$0")/.." && pwd)
completion_script="$test_root/.shrc_scripts/svc_completion.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT

ln -s "$test_root/tests/test_svc_completion.sh" "$test_tmp/systemctl"
export PATH="$test_tmp:$PATH"

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

. "$completion_script"

assert_equal 'complete -F _svc_bash_complete svc' "$(complete -p svc)" \
    'Bash completion is registered'

COMP_WORDS=(svc s)
COMP_CWORD=1
_svc_bash_complete
assert_equal $'sa\nsp' "$(printf '%s\n' "${COMPREPLY[@]}")" \
    'Bash action completion filters by prefix'

export SVC_TEST_SYSTEM_UNITS='zeta.service shared.service app-foo\x2dbar.service'
export SVC_TEST_USER_UNITS='alpha.service shared.service'

COMP_WORDS=(svc sa '')
COMP_CWORD=2
_svc_bash_complete
expected_all=$'alpha.service\napp-foo\\x2dbar.service\nshared.service\nzeta.service'
assert_equal "$expected_all" "$(printf '%s\n' "${COMPREPLY[@]}")" \
    'Bash service completion merges scopes and preserves escaped names'

COMP_WORDS=(svc pu '')
COMP_CWORD=2
_svc_bash_complete
assert_equal $'alpha.service\nshared.service' "$(printf '%s\n' "${COMPREPLY[@]}")" \
    'Bash explicit-user completion only lists user units'

assert_equal 1 "$(command grep -c '^svc_completion$' "$test_root/.shrc_scripts/manifest.txt")" \
    'completion module appears once in the manifest'

if command -v zsh >/dev/null 2>&1; then
    zsh_output=$(zsh -f -c '
        autoload -Uz compinit
        compinit -D
        . "$1"
        [[ "${_comps[svc]:-}" = _svc_zsh_complete ]] || exit 20
        _describe() { print -rl -- "${candidates[@]}"; }
        words=(svc sa "")
        CURRENT=3
        _svc_zsh_complete
    ' zsh "$completion_script")
    zsh_status=$?
    assert_equal 0 "$zsh_status" 'Zsh completion is registered and runs'
    assert_equal "$expected_all" "$zsh_output" \
        'Zsh service completion receives merged candidates'
else
    printf '# zsh unavailable; Zsh behavior checks skipped\n'
fi

printf '1..%d\n' "$tests"
if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

#!/usr/bin/env bash

# Usage: source scripts/source_shrc.sh
# The file must be sourced because a child process cannot modify its parent shell.

if [ -n "${BASH_VERSION:-}" ]; then
    if [ "${BASH_SOURCE[0]}" = "$0" ]; then
        echo "Usage: source ${BASH_SOURCE[0]}" >&2
        exit 2
    fi
    _shrc_dev_loader="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
    case "${ZSH_EVAL_CONTEXT:-}" in
        *:file*) ;;
        *) echo "Usage: source scripts/source_shrc.sh" >&2; return 2 ;;
    esac
    eval '_shrc_dev_loader="${(%):-%x}"'
else
    echo "source_shrc.sh supports Bash and Zsh" >&2
    return 2
fi

_shrc_dev_root=$(CDPATH= builtin cd -P -- "$(command dirname -- "$_shrc_dev_loader")/.." >/dev/null && builtin pwd -P) || return 1
. "$_shrc_dev_root/.shrc" || return 1
SHRC_SCRIPTS_HOME="$_shrc_dev_root/.shrc_scripts"

echo "Loaded development shrc: $_shrc_dev_root"
unset _shrc_dev_loader _shrc_dev_root

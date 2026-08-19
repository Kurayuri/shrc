#!/bin/bash

# This file is sourced by .shrc. It supports both Bash and Zsh.

_svc_completion_list_service_units()
{
    local scope="$1"

    if [ "$scope" = user ]; then
        command systemctl --user --root=/ list-unit-files --type=service \
            --no-legend --no-pager 2>/dev/null
    else
        command systemctl --system --root=/ list-unit-files --type=service \
            --no-legend --no-pager 2>/dev/null
    fi | command awk '$1 ~ /\.service$/ { print $1 }'
}

_svc_completion_candidates()
{
    local kind="${1:-actions}"
    local scope="${2:-all}"

    case "$kind" in
        actions)
            command printf '%s\n' av dv l lu li sa sp rd rs rl p pu pi j jx
            ;;
        services)
            case "$scope" in
                all)
                    command sort -u \
                        <(_svc_completion_list_service_units system) \
                        <(_svc_completion_list_service_units user)
                    ;;
                system|user)
                    _svc_completion_list_service_units "$scope" | command sort -u
                    ;;
                *)
                    echo "svc completion: invalid service scope: $scope" >&2
                    return 2
                    ;;
            esac
            ;;
        *)
            echo "svc completion: invalid candidate kind: $kind" >&2
            return 2
            ;;
    esac
}

if [ -n "${BASH_VERSION:-}" ]; then
    _svc_bash_complete()
    {
        local action="${COMP_WORDS[1]:-}"
        local candidate=""
        local current="${COMP_WORDS[COMP_CWORD]:-}"
        local kind=""
        local scope=""
        COMPREPLY=()

        if [ "$COMP_CWORD" -eq 1 ]; then
            kind=actions
        elif [ "$COMP_CWORD" -eq 2 ]; then
            kind=services
            case "$action" in
                av|dv|sa|sp|rs|rl|p|j|jx) scope=all ;;
                lu|li|pu|pi) scope=user ;;
                *) return 0 ;;
            esac
        else
            return 0
        fi

        while IFS= read -r candidate; do
            case "$candidate" in
                "$current"*) COMPREPLY+=("$candidate") ;;
            esac
        done < <(_svc_completion_candidates "$kind" "$scope")
    }

    complete -F _svc_bash_complete svc
elif [ -n "${ZSH_VERSION:-}" ]; then
    _svc_zsh_complete()
    {
        local action="${words[2]:-}"
        local candidate=""
        local kind=""
        local scope=""
        local -a candidates

        if (( CURRENT == 2 )); then
            kind=actions
        elif (( CURRENT == 3 )); then
            kind=services
            case "$action" in
                av|dv|sa|sp|rs|rl|p|j|jx) scope=all ;;
                lu|li|pu|pi) scope=user ;;
                *) return 0 ;;
            esac
        else
            return 0
        fi

        while IFS= read -r candidate; do
            [ -n "$candidate" ] && candidates+=("$candidate")
        done < <(_svc_completion_candidates "$kind" "$scope")
        _describe 'svc value' candidates
    }

    if (( $+functions[compdef] )); then
        compdef _svc_zsh_complete svc
    fi
fi

#!/bin/bash

_svc_list_i()
{
    command find "$HOME/.config/systemd/user" -maxdepth 1 -name '*.service' -printf '%f\n' 2>/dev/null \
        | command grep -e "${1:-}"
}

_svc_service_unit_name()
{
    case "$1" in
        *.service) command printf '%s\n' "$1" ;;
        *) command printf '%s.service\n' "$1" ;;
    esac
}

_svc_list_unit_file()
{
    local scope="$1"
    local unit="$2"

    if [ "$scope" = user ]; then
        command systemctl --user --root=/ list-unit-files --type=service \
            --no-legend --no-pager -- "$unit" 2>/dev/null
    else
        command systemctl --system --root=/ list-unit-files --type=service \
            --no-legend --no-pager -- "$unit" 2>/dev/null
    fi
}

_svc_unit_file_exists()
{
    local scope="$1"
    local unit="$2"
    local template=""
    local match=""

    match=$(_svc_list_unit_file "$scope" "$unit") || match=""
    if [ -n "$match" ]; then
        return 0
    fi

    case "$unit" in
        *@*.service)
            template="${unit%%@*}@.service"
            if [ "$template" != "$unit" ]; then
                match=$(_svc_list_unit_file "$scope" "$template") || match=""
                [ -n "$match" ] && return 0
            fi
            ;;
    esac

    return 1
}

_svc_resolve_service_scope()
{
    local service="$1"
    local unit=""
    local in_system=0
    local in_user=0

    if [ -z "$service" ]; then
        echo "svc: a service name is required" >&2
        return 2
    fi

    unit=$(_svc_service_unit_name "$service") || return 1
    _svc_unit_file_exists system "$unit" && in_system=1
    _svc_unit_file_exists user "$unit" && in_user=1

    if [ "$in_system" -eq 1 ]; then
        if [ "$in_user" -eq 1 ]; then
            echo "svc: '$service' exists in both system and user scopes; using system scope" >&2
        fi
        command printf '%s\n' system
    elif [ "$in_user" -eq 1 ]; then
        command printf '%s\n' user
    else
        echo "svc: service not found in system or user scope: $service" >&2
        return 1
    fi
}

_svc_run_scoped()
{
    local action="$1"
    local service="${2:-}"
    local scope=""

    if [ -z "$service" ]; then
        echo "Usage: svc <av|dv|sa|sp|rs|rl|p> <service> [systemctl_args...]" >&2
        return 2
    fi

    shift 2
    scope=$(_svc_resolve_service_scope "$service") || return $?

    if [ "$scope" = user ]; then
        if [ "$action" = status ]; then
            command systemctl --user status --no-pager "$service" "$@"
        else
            command systemctl --user "$action" "$service" "$@"
        fi
    else
        if [ "$action" = status ]; then
            command systemctl status --no-pager "$service" "$@"
        else
            command systemctl "$action" "$service" "$@"
        fi
    fi
}

svc()
{
    local action="${1:-}"

    case "$action" in
        av) shift; _svc_run_scoped enable "$@" ;;
        dv) shift; _svc_run_scoped disable "$@" ;;
        l) shift; command systemctl list-units --no-pager --type=service --all "$@" ;;
        lu) shift; command systemctl list-units --no-pager --type=service --all --user "$@" ;;
        li) shift; _svc_list_i "$@" ;;
        sa) shift; _svc_run_scoped start "$@" ;;
        sp) shift; _svc_run_scoped stop "$@" ;;
        rd) shift; command systemctl daemon-reload "$@" ;;
        rs) shift; _svc_run_scoped restart "$@" ;;
        rl) shift; _svc_run_scoped reload "$@" ;;
        p) shift; _svc_run_scoped status "$@" ;;
        pu) shift; command systemctl status --no-pager --user "$@" ;;
        pi)
            shift
            local pattern="${1:-}"
            [ $# -gt 0 ] && shift
            command systemctl status --no-pager --user $(_svc_list_i "$pattern") "$@"
            ;;
        j)
            shift
            local service="${1:-}"
            [ $# -gt 0 ] && shift
            command journalctl --no-pager --unit "$service" --user-unit "$service" "$@"
            ;;
        jx)
            shift
            local service_pattern="${1:-}"
            [ $# -gt 0 ] && shift
            command journalctl --no-pager --unit "*$service_pattern*" \
                --user-unit "*$service_pattern*" "$@"
            ;;
        *) command systemctl "$@" ;;
    esac
}

svc "$@"

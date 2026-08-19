#!/bin/bash

px()
{
    local ps_args="aux"
    local processed_args=()

    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-ps" ]]; then
            if [[ -z "${2:-}" ]]; then
                echo "Error: -ps option requires arguments (e.g., 'auxww')." >&2
                return 1
            fi
            ps_args="$2"
            shift 2
        else
            processed_args+=("$1")
            shift
        fi
    done

    set -- "${processed_args[@]}"

    local user_pattern=".*"
    local current_user="${USER:-}"

    case "${1:-}" in
        -u)
            if [ -z "${2:-}" ]; then
                echo "Error: -u option requires a username." >&2
                echo "Usage: px [-ps ps_args] [-u user | -ur | -ui | -up] [r|ra|l|la] [search_string]" >&2
                return 1
            fi
            user_pattern="^$2$"
            shift 2
            ;;
        -ur)
            user_pattern="^root$"
            shift
            ;;
        -ui)
            user_pattern="^${current_user}$"
            shift
            ;;
        -up)
            if [ "$current_user" = "root" ]; then
                user_pattern="^root$"
            else
                user_pattern="^(root|${current_user})$"
            fi
            shift
            ;;
    esac

    local stat_pattern=".*"
    local cmd_pattern=".*"
    local search_type="prefix"
    local search_scope="col11"
    local search_string=""
    local safe_search_pattern=""

    if [ $# -gt 0 ]; then
        case "$1" in
            l)
                stat_pattern="^[RSD]"
                ;;
            la)
                stat_pattern="^[RSD]"
                search_type="contains"
                search_scope="full"
                ;;
            r)
                stat_pattern="^[R]"
                ;;
            ra)
                stat_pattern="^[R]"
                search_type="contains"
                search_scope="full"
                ;;
            *)
                echo "Error: Unknown argument '$1'" >&2
                echo "Usage: px [-ps ps_args] [-u user | -ur | -ui | -up] [r|ra|l|la] [search_string]" >&2
                return 1
                ;;
        esac
        shift

        if [ $# -gt 0 ]; then
            search_string="$1"

            local first_char="${search_string:0:1}"
            local rest_chars="${search_string:1}"
            safe_search_pattern="[${first_char}]${rest_chars}"

            if [ "$search_type" = "prefix" ]; then
                cmd_pattern="^${safe_search_pattern}"
            else
                cmd_pattern="${safe_search_pattern}"
            fi
        fi
    fi

    local awk_script='
        NR == 1 { print; next }
        (user_regex != ".*" && $1 !~ user_regex) { next }
        ($8 ~ stat_regex) {
            if (scope == "col11") {
                if ($11 ~ cmd_regex) {
                    print
                }
            } else {
                cmd = ""
                for (i = 11; i <= NF; i++) {
                    cmd = cmd $i " "
                }
                if (cmd ~ cmd_regex) {
                    print
                }
            }
        }
    '

    command ps $ps_args \
        | command awk -v user_regex="$user_pattern" \
                      -v stat_regex="$stat_pattern" \
                      -v cmd_regex="$cmd_pattern" \
                      -v scope="$search_scope" \
                      "$awk_script" \
        | {
            local header=""
            IFS= read -r header || return 1
            command printf '%s\n' "$header"

            if [ -z "$search_string" ]; then
                command cat
                return $?
            fi

            command grep --color=auto -E -e "$safe_search_pattern"
            local grep_status=$?
            [ "$grep_status" -eq 1 ] && return 0
            return "$grep_status"
        }
}

px "$@"

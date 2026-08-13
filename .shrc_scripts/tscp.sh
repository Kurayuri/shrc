#!/bin/bash

tscp()
{
    # tar scp: scp stream transfer with tar, speeding up dummy files scp
    # --------------------------------------------------------------------------
    # Helper function: Executes a command pipeline with retry logic.
    #
    # Arguments:
    #   $1: The first command in the pipeline (string). This command's stderr
    #       is monitored for the "file changed" message.
    #   $2: The second command in the pipeline (string).
    #   $3: A context message for logging, e.g., "Local file" or "Remote file".
    #   $4: The maximum number of retry attempts.
    # --------------------------------------------------------------------------
    local tscp_help="Usage: tscp [-z] [-1] <local_src> <remote> <remote_dst>
       tscp -r [-z] [-1] <remote> <remote_src> <local_dst>
Options:
     -z : Use gzip compression for the transfer.
     -1 : Disable retries (only attempt once).
     -r : Pull mode (remote to local). Without this flag, tscp operates in push mode (local to remote)."

    _tscp_execute() {
        local cmd1="$1"
        local cmd2="$2"
        local context_msg="$3"
        local max_retries="$4"

        for (( attempt=1; attempt<=max_retries; attempt++ )); do
            local temp_err_file
            temp_err_file=$(mktemp)
            
            # Execute the pipeline.
            # A { ...; } group is used to ensure the stderr redirection applies
            # to the command executed by eval, not to eval itself.
            (set -o pipefail; { eval "$cmd1"; } 2> "$temp_err_file" | eval "$cmd2")
            local pipe_status=$?

            # Check for the specific "file changed" warning.
            if grep -q "file changed as we read it" "$temp_err_file"; then
                # If this was the last attempt, report failure.
                if (( attempt >= max_retries )); then
                    echo "tscp: ${context_msg} changed, max attempts (${max_retries}) reached. Aborting." >&2
                    cat "$temp_err_file" >&2
                    rm -f "$temp_err_file"
                    return 1
                else
                    # Otherwise, print a retry message and try again.
                    echo "tscp: ${context_msg} changed, retrying... (${attempt}/${max_retries})" >&2
                    rm -f "$temp_err_file"
                    sleep 1
                    continue
                fi
            fi

            # If a different, non-recoverable error occurred, fail immediately.
            if [[ $pipe_status -ne 0 ]]; then
                echo "tscp: Transfer failed with a non-recoverable error." >&2
                cat "$temp_err_file" >&2
                rm -f "$temp_err_file"
                return $pipe_status
            fi
            
            # If we reach here, the command was successful.
            rm -f "$temp_err_file"
            return 0 # Success
        done
        
        # This line should only be reached if the loop condition fails unexpectedly.
        return 1
    }

    # --------------------------------------------------------------------------
    # Main function logic
    # --------------------------------------------------------------------------
    local OPTIND
    local use_compression=false
    local pull_mode=false
    local no_retry=false
    local tar_opts_create="cf"
    local tar_opts_extract="xf"

    # Process command-line options.
    while getopts "zr1" opt; do
        case $opt in
            z) use_compression=true; tar_opts_create="czf"; tar_opts_extract="xzf" ;;
            r) pull_mode=true ;;
            1) no_retry=true ;;
            \?) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
        esac
    done
    shift $((OPTIND-1))

    # Set max_retries to 1 if the -1 flag is present, otherwise default to 5.
    local max_retries=5
    if [ "$no_retry" = true ]; then
        max_retries=1
    fi

    if [ "$pull_mode" = true ]; then
        # Pull mode: remote -> local
        local remote=$1 src=$2 dst=$3
        if [ -z "$remote" ] || [ -z "$src" ] || [ -z "$dst" ]; then
            echo $tscp_help
            return 1
        fi
        
        # Define the commands for pull mode.
        local cmd1="ssh '$remote' \"tar $tar_opts_create - -C '$(dirname "$src")' '$(basename "$src")'\""
        local cmd2="tar '$tar_opts_extract' - -C '$dst'"

        # Execute using the helper function.
        _tscp_execute "$cmd1" "$cmd2" "Remote file" "$max_retries"
    else
        # Push mode: local -> remote
        local src=$1 remote=$2 dst=$3
        if [ -z "$src" ] || [ -z "$remote" ] || [ -z "$dst" ]; then
            echo $tscp_help
            return 1
        fi
        
        # Define the commands for push mode.
        local cmd1="tar '$tar_opts_create' - '$src'"
        local cmd2="ssh '$remote' \"tar '$tar_opts_extract' - -C '$dst'\""
        
        # Execute using the helper function.
        _tscp_execute "$cmd1" "$cmd2" "Local file" "$max_retries"
    fi
}

tscp "$@"

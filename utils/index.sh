#!/bin/sh

# Public method to load and parse a .env file into environment variables
load_env() {
    local env_file="$1"
    [ -f "$env_file" ] || return 0

    while read -r line || [ -n "$line" ]; do
        # Remove carriage return for CRLF compatibility
        line=$(echo "$line" | tr -d '\r')
        # Skip comments and empty lines
        case "$line" in
            \#*|"") continue ;;
        esac
        key="${line%%=*}"
        val="${line#*=}"
        key=$(echo "$key" | tr -d ' \t')
        val=$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        export "$key=$val"
    done < "$env_file"
}

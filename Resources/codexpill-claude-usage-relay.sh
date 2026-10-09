#!/bin/sh
# Claude Code status line relay for CodexPill.
#
# Claude Code runs this as its statusLine command and pipes session JSON on
# stdin. The relay copies only the 5-hour and 7-day used percentages and reset
# times into CodexPill's app-support folder, then hands the untouched stdin to
# the user's previous status line command (first argument, if any) and exits
# with its status. A failed CodexPill write never changes the status line.

input=$(cat; printf x)
input=${input%x}

usage_file="$HOME/Library/Application Support/CodexPill/claude-usage.json"

extract_number() {
    value=$(printf '%s' "$input" | /usr/bin/plutil -extract "rate_limits.$1" raw -o - - 2>/dev/null) || return 1
    case $value in
        *[!0-9.]* | *.*.* | '') return 1 ;;
        *[0-9]*) printf '%s' "$value" ;;
        *) return 1 ;;
    esac
}

window_json() {
    used=$(extract_number "$1.used_percentage") || return 1
    resets=$(extract_number "$1.resets_at") || return 1
    printf '"%s":{"used_percentage":%s,"resets_at":%s}' "$1" "$used" "$resets"
}

write_usage() {
    if printf '%s' "$input" | /usr/bin/plutil -extract rate_limits json -o /dev/null - 2>/dev/null; then
        windows=""
        for name in five_hour seven_day; do
            if window=$(window_json "$name"); then
                windows="${windows:+$windows,}$window"
            fi
        done
    elif [ -e "$usage_file" ]; then
        return 0
    else
        windows=""
    fi

    umask 077
    directory=${usage_file%/*}
    mkdir -p "$directory" || return 1
    temporary="$directory/.claude-usage.json.$$"
    printf '{"schema":1,"captured_at":%s,"rate_limits":{%s}}\n' "$(date +%s)" "$windows" > "$temporary" &&
        mv -f "$temporary" "$usage_file" ||
        { rm -f "$temporary"; return 1; }
}

(write_usage) >/dev/null 2>&1

if [ -n "$1" ]; then
    printf '%s' "$input" | /bin/sh -c "$1"
fi

#!/usr/bin/env bash
set -euo pipefail

show_help() {
    cat <<'USAGE'
Usage: wtouch.sh [OPTION]... FILE...

  -a                   Change the access time only
  -m                   Change the modification time only
  -c, --no-create      Do not create any files
  -d STRING            Parse STRING as an explicit timestamp (YYYY-MM-DD[ HH:MM[:SS]])
  -t STAMP             Parse STAMP in [[CC]YY]MMDDhhmm[.ss] format
  -r FILE              Use FILE's access/modification times
      --               Treat all following arguments as literal paths
  -V, --version        Show version information
  -P, --path           Show the resolved script path
  -h, --help           Show this help message

This script delegates timestamp updates to the system `touch` utility so it
inherits the platform behaviour of that command.
USAGE
}

VERSION="1.0.0"
cmd=(touch)
paths=()
show_version=0
show_path=0

resolve_script_path() {
    local source="$0"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$source"
        return
    fi
    if command -v readlink >/dev/null 2>&1; then
        local resolved
        if resolved=$(readlink -f "$source" 2>/dev/null); then
            printf '%s\n' "$resolved"
            return
        fi
    fi
    case "$source" in
        /*)
            printf '%s\n' "$source"
            ;;
        *)
            printf '%s/%s\n' "$PWD" "$source"
            ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a)
            cmd+=("-a")
            shift
            ;;
        -m)
            cmd+=("-m")
            shift
            ;;
        -c|--no-create)
            cmd+=("-c")
            shift
            ;;
        -d|-t|-r)
            if [[ $# -lt 2 ]]; then
                echo "wtouch.sh: option '$1' requires an argument" >&2
                exit 1
            fi
            cmd+=("$1" "$2")
            shift 2
            ;;
        -V|--version)
            show_version=1
            shift
            ;;
        -P|--path)
            show_path=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                paths+=("$1")
                shift
            done
            break
            ;;
        -*)
            echo "wtouch.sh: unrecognised option '$1'" >&2
            echo "Try 'wtouch.sh --help' for more information." >&2
            exit 1
            ;;
        *)
            paths+=("$1")
            shift
            ;;
    esac
done

if [[ $show_version -eq 1 ]]; then
    printf 'wtouch version %s\n' "$VERSION"
fi

if [[ $show_path -eq 1 ]]; then
    resolved=""
    if ! resolved=$(resolve_script_path); then
        echo "wtouch.sh: failed to determine script path" >&2
        exit 1
    fi
    printf 'wtouch path %s\n' "$resolved"
fi

if [[ ${#paths[@]} -eq 0 ]]; then
    if [[ $show_version -eq 1 || $show_path -eq 1 ]]; then
        exit 0
    fi
    echo "wtouch.sh: missing file operand" >&2
    echo "Try 'wtouch.sh --help' for more information." >&2
    exit 1
fi

exec "${cmd[@]}" "${paths[@]}"

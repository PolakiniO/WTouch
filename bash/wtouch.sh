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
  -h, --help           Show this help message

This script delegates timestamp updates to the system `touch` utility so it
inherits the platform behaviour of that command.
USAGE
}

cmd=(touch)
paths=()

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

if [[ ${#paths[@]} -eq 0 ]]; then
    echo "wtouch.sh: missing file operand" >&2
    echo "Try 'wtouch.sh --help' for more information." >&2
    exit 1
fi

exec "${cmd[@]}" "${paths[@]}"

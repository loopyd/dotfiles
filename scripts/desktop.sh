#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-}"
case "${ACTION}" in
    -h|--help|help|'')
        printf '%s\n' 'Usage: desktop.sh <install|update|uninstall|check|export> [options]' \
            'Install/update import selected settings; export captures them.' \
            'Uninstall restores an explicitly supplied --input backup directory.' \
            'Check previews the import without changing settings. --dry-run is supported.'
        exit 0 ;;
    install|update|uninstall|check|export) shift ;;
    *) printf '%s\n' 'Unknown desktop action' >&2; exit 2 ;;
esac

if [[ "${ACTION}" == export ]]; then
    source "${SCRIPT_DIR}/desktop/capture.sh"
    main "$@"
else
    if [[ "${ACTION}" == uninstall ]]; then
        has_input=false
        for argument in "$@"; do [[ "${argument}" != --input ]] || has_input=true; done
        [[ "${has_input}" == true ]] || { printf '%s\n' 'Desktop uninstall requires --input <pre-install backup>; no settings reset.' >&2; exit 2; }
    fi
    source "${SCRIPT_DIR}/desktop/preferences.sh"
    if [[ "${ACTION}" == check ]]; then
        main "$@" --dry-run
    else
        main "$@"
    fi
fi

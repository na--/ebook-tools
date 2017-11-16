#!/usr/bin/env bash

set -eEuo pipefail

# Use newlines as a separator by default
: "${ISBN_RET_SEPARATOR:=$'\n'}"

# shellcheck source=./lib.sh
. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib.sh"

for arg in "$@"; do
	case $arg in
		-irs=*|--isbn-return-separator=*) ISBN_RET_SEPARATOR="${arg#*=}" ;;
		-*) handle_script_arg "$arg" ;;
		*) break ;;
	esac
	shift # past argument=value or argument with no value
done
unset -v arg

if [[ "$#" == "0" ]]; then
	find_isbns
else
	search_file_for_isbns "$1"
fi

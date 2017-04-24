#!/usr/bin/env bash

set -euo pipefail

DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=./lib.sh
. "$DIR/lib.sh"

ISBN_RET_SEPARATOR="\n"

#TODO: add options, help
#TODO: add option to limit the number of ISBNs?

if [[ "$#" == "0" ]]; then
	find_isbns
else
	search_file_for_isbns "$1"
fi

#!/usr/bin/env bash

set -euo pipefail

DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=./lib.sh
. "$DIR/lib.sh"

# Overwrite the global variables for ISBN-optimized OCRs
OCR_ONLY_FIRST_LAST_PAGES="false"

for arg in "$@"; do
	case $arg in
		-*|--*) handle_script_arg "$arg" ;;
		*) break ;;
	esac
	shift # past argument=value or argument with no value
done
unset -v arg

input_file="$1"
output_file="${2:-}"
mime_type=$(file --brief --mime-type "$input_file")

if [[ "$output_file" != "" ]]; then
    if [[ "${output_file##*.}" != "txt" ]]; then
        echo "Error: the ouput file needs to have a .txt extension!"
        exit 1
    fi

    convert_to_txt "$input_file" "$output_file" "$mime_type"
else
    tmptxtfile="$(mktemp --suffix='.txt')"
    decho "Created a temporary file '$tmptxtfile'"

    convert_to_txt "$input_file" "$tmptxtfile" "$mime_type"
    cat "$tmptxtfile"

    decho "Removing the temporary file '$tmptxtfile'"
    rm "$tmptxtfile"
fi
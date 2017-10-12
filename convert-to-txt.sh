#!/usr/bin/env bash

set -euo pipefail

DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=./lib.sh
. "$DIR/lib.sh"

# Overwrite the global variables for ISBN-optimized OCRs
OCR_COMMAND="tesseract"
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
is_tmp_file=false

if [[ "$output_file" == "" ]]; then
    is_tmp_file=true
    output_file=$(mktemp --suffix='.txt')
    decho "Created a temporary file '$output_file'"
elif [[ "${output_file##*.}" != "txt" ]]; then
    echo "Error: the ouput file needs to have a .txt extension!"
    exit 1
fi
args=("$input_file" "$output_file" "$mime_type")

if [[ "$OCR_ENABLED" == "always" ]]; then
    decho "OCR=always, first try OCR then conversion"
    ocr_file "${args[@]}" || convert_to_txt "${args[@]}"
elif [[ "$OCR_ENABLED" == "true" ]]; then
    decho "OCR=true, first try conversion and then OCR"
    if convert_to_txt "${args[@]}" && grep -qiE "[[:alnum:]]+" "$output_file"; then
        decho "conversion successfull, will not try OCR"
    else
        ocr_file "${args[@]}"
    fi
else
    decho "OCR=false, try only conversion"
    convert_to_txt "${args[@]}"
fi

if [[ "$is_tmp_file" == true ]]; then
    cat "$output_file"

    decho "Removing the temporary file '$output_file'"
    rm "$output_file"
fi
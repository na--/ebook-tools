#!/usr/bin/env bash

set -eEuo pipefail

# OCR all pages by default
: "${OCR_ONLY_FIRST_LAST_PAGES:="false"}"

# shellcheck source=./lib.sh
. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib.sh"

tesseract_wrapper () {
	tesseract "$1" stdout > "$2"
}

for arg in "$@"; do
	case $arg in
		-*) handle_script_arg "$arg" ;;
		*) break ;;
	esac
	shift # past argument=value or argument with no value
done
unset -v arg

if [[ "$#" == "0" ]]; then
	echo "Please specify calibre library folder(s)"
	exit 1
fi

input_file="$1"
output_file="${2:-}"
mime_type=$(file --brief --mime-type "$input_file")
is_tmp_file=false

if [[ "$output_file" == "" ]]; then
	is_tmp_file=true
	output_file=$(mktemp --suffix='.txt')
	decho "Created a temporary file '$output_file'"
elif [[ "${output_file##*.}" != "txt" ]]; then
	echo "Error: the output file needs to have a .txt extension!"
	exit 1
fi
args=("$input_file" "$output_file" "$mime_type")

if [[ "$OCR_ENABLED" == "always" ]]; then
	decho "OCR=always, first try OCR then conversion"
	if ! ocr_file "${args[@]}"; then
		convert_to_txt "${args[@]}"
	fi
elif [[ "$OCR_ENABLED" == "true" ]]; then
	decho "OCR=true, first try conversion and then OCR"
	if convert_to_txt "${args[@]}" && grep -qiE "[[:alnum:]]+" "$output_file"; then
		decho "conversion successful, will not try OCR"
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
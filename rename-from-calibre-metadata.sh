#!/bin/bash

set -euo pipefail

DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=./lib.sh
. "$DIR/lib.sh"


OUTPUT_FOLDER=""
SAVE_METADATA="recreate" # possible values: none, opfcopy, recreate

for arg in "$@"; do
	case $arg in
		-o=*|--output-folder=*) OUTPUT_FOLDER="${arg#*=}" ;;
		-sm=*|--save-metadata=*) SAVE_METADATA="${arg#*=}" ;;
		-*|--*) handle_script_arg "$arg" ;;
		*) break ;;
	esac
	shift # past argument=value or argument with no value
done
unset -v arg


find "$@" -type f ! -name "*.opf" ! -name "cover.jpg" -print0 | sort -z "${FILE_SORT_FLAGS[@]}" | while IFS= read -r -d '' book_path
do
    metadata_path="$(dirname "$book_path")/metadata.opf"
    if [[ ! -f "$metadata_path" ]]; then
        decho "Skipping file '$book_path' - no metadata.opf present!"
        continue
    fi

    decho "Found file '$book_path' with metadata.opf present, parsing metadata..."
    declare -A d=(
        ["EXT"]="${book_path##*.}"
        ["TITLE"]=$(xpath -q -e '//dc:title/text()' < "$metadata_path")
        ["AUTHORS"]=$(xpath -q -e '//dc:creator/text()' < "$metadata_path" | stream_concat ', ')
        ["SERIES"]=$(xpath -q -e 'concat(//meta[@name="calibre:series"]/@content," #",//meta[@name="calibre:series_index"]/@content)' < "$metadata_path" | sed -E 's/\s*#\s*$//')
        ["PUBLISHED"]=$(xpath -q -e '//dc:date/text()' < "$metadata_path")
        ["ISBN"]=$(xpath -q -e '//dc:identifier[@opf:scheme="ISBN"]/text()' < "$metadata_path")
    )

    if [[ "${d['ISBN']}" == "" ]]; then
        d['ISBN']=$(find_isbns < "$metadata_path")
    fi

    decho "Parsed metadata:"
	for key in "${!d[@]}"; do
		echo "${d[${key}]}" | debug_prefixer "    ${key}" 25
	done

    new_name="$(eval echo "$OUTPUT_FILENAME_TEMPLATE")"
    new_path="$(unique_filename "${OUTPUT_FOLDER:-$(dirname "$book_path")}" "$new_name")"
	decho "Moving file to '$new_path'..."

    move_or_link_file "$book_path" "$new_path"
    case "$SAVE_METADATA" in
        recreate)
            {
                echo "Title               : ${d['TITLE']}"
                echo "Author(s)           : ${d['AUTHORS']}"
                echo "Series              : ${d['SERIES']}"
                echo "Published           : ${d['PUBLISHED']}"
                echo "ISBN                : ${d['ISBN']}"
                echo "Old file path       : $book_path"
                echo "Metadata source     : metadata.opf"
            } | grep -vE " : $" > "${new_path}.$OUTPUT_METADATA_EXTENSION"
        ;;
		opfcopy) cp --no-clobber "$metadata_path" "${new_path}.$OUTPUT_METADATA_EXTENSION" ;;
		*) decho "Metadata was not copied or recreated" ;;
	esac
done

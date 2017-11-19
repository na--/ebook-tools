#!/usr/bin/env bash

set -eEuo pipefail

: "${OUTPUT_FOLDER:=$(pwd)}"
: "${SAVE_METADATA:="recreate"}" # possible values: none, opfcopy, recreate

# shellcheck source=./lib.sh
. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib.sh"

for arg in "$@"; do
	case $arg in
		-o=*|--output-folder=*) OUTPUT_FOLDER="${arg#*=}" ;;
		-sm=*|--save-metadata=*) SAVE_METADATA="${arg#*=}" ;;
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

gm() {
    python2 -c "from lxml.etree import parse; from sys import stdin; print((u'\\n'.join(parse(stdin).xpath('$2'))).encode('utf-8'))" < "$1"
}

find "$@" -type f ! -name "*.opf" ! -name "cover.jpg" -print0 | sort -z ${FILE_SORT_FLAGS[@]:+"${FILE_SORT_FLAGS[@]}"} | while IFS= read -r -d '' book_path
do
    metadata_path="$(dirname "$book_path")/metadata.opf"
    if [[ ! -f "$metadata_path" ]]; then
        decho "Skipping file '$book_path' - no metadata.opf present!"
        continue
    fi

    decho "Found file '$book_path' with metadata.opf present, parsing metadata..."

    declare -A d=( ["EXT"]="${book_path##*.}" )
    d["TITLE"]=$(gm "$metadata_path" '//*[local-name()="title"]/text()')
    d["AUTHORS"]=$(gm "$metadata_path" '//*[local-name()="creator"]/text()' | stream_concat ', ')
    d["SERIES"]=$(gm "$metadata_path" '//*[local-name()="meta"][@name="calibre:series"]/@content')
    if [[ "${d['SERIES']}" != "" ]]; then
        d["SERIES"]="${d['SERIES']} #$(gm "$metadata_path" '//*[local-name()="meta"][@name="calibre:series_index"]/@content')"
    fi
    d["PUBLISHED"]=$(gm "$metadata_path" '//*[local-name()="date"]/text()')
    d["ISBN"]=$(gm "$metadata_path" '//*[local-name()="identifier"][@*[local-name()="scheme" and .="ISBN"]]/text()')

    if [[ "${d['ISBN']}" == "" ]]; then
        d['ISBN']=$(find_isbns < "$metadata_path")
    fi

    decho "Parsed metadata:"
	for key in "${!d[@]}"; do
        #TODO: fix this properly
        d["$key"]=$(echo "${d[${key}]}" | sed -e 's/[\\/\*\?<>\|\x01-\x1F\x7F\x22\x24\x60]/_/g' | cut -c 1-100)
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

#!/usr/bin/env bash

set -euo pipefail

: "${FOLDER_PATTERN:="%05d000"}"
: "${START_NUMBER:=0}"
: "${OUTPUT_FOLDER:=$(pwd)}"
: "${FILES_PER_FOLDER:=1000}"

# shellcheck source=./lib.sh
. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib.sh"

for arg in "$@"; do
	case $arg in
		-o=*|--output-folder=*) OUTPUT_FOLDER="${arg#*=}" ;;
		-sn=*|--start-number=*) START_NUMBER="${arg#*=}" ;;
		-fp=*|--folder-pattern=*) FOLDER_PATTERN="${arg#*=}" ;;
		-fpf=*|--files-per-folder=*) FILES_PER_FOLDER="${arg#*=}" ;;
		-*|--*) handle_script_arg "$arg" ;;
		*) break ;;
	esac
	shift # past argument=value or argument with no value
done
unset -v arg
if [[ "$#" == "0" ]]; then
	echo "Please specify folders with files to split"
	exit 1
fi


current_folder_num="$START_NUMBER"

find "$@" -type f ! -name "*.meta" | sort "${FILE_SORT_FLAGS[@]}" | {
	while true; do
		chunk=$(cat_n "$FILES_PER_FOLDER")
		numfiles=$(echo "$chunk" | wc -l)
		decho "Found $numfiles number of files..."
		if (( numfiles < FILES_PER_FOLDER )); then
			decho "Insufficient for a new pack, breaking!"
			break
		fi

		#shellcheck disable=SC2059
		current_folder="$(printf "$FOLDER_PATTERN" "$current_folder_num")"
		current_folder_num=$((current_folder_num+1))
		decho "Creating folder '$OUTPUT_FOLDER/$current_folder' and '$OUTPUT_FOLDER/$current_folder.meta'..."
		$DRY_RUN || mkdir "$OUTPUT_FOLDER/$current_folder"
		$DRY_RUN || mkdir "$OUTPUT_FOLDER/$current_folder.meta"

		echo "$chunk" | while IFS= read -r file_to_move || [[ -n "$file_to_move" ]] ; do
			decho "Moving file '$file_to_move' to '$OUTPUT_FOLDER/$current_folder/' and the meta file to '$OUTPUT_FOLDER/$current_folder.meta/'"
			$DRY_RUN || mv --no-clobber "$file_to_move" "$OUTPUT_FOLDER/$current_folder/"
			$DRY_RUN || mv --no-clobber "$file_to_move.meta" "$OUTPUT_FOLDER/$current_folder.meta/"
		done
	done
}


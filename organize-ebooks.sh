#!/usr/bin/env bash

set -euo pipefail

DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=./lib.sh
. "$DIR/lib.sh"

OUTPUT_FOLDER="$(pwd)"
OUTPUT_FOLDER_SEPARATE_UNSURE=false
OUTPUT_FOLDER_UNSURE="$(pwd)"
#shellcheck disable=SC2016
FILENAME_TEMPLATE='"${d[AUTHORS]// & /, } - ${d[SERIES]+[${d[SERIES]}] - }${d[TITLE]/:/ -}${d[PUBLISHED]+ (${d[PUBLISHED]%%-*})}${d[ISBN]+ [${d[ISBN]}]}.${d[EXT]}"'
#shellcheck disable=SC2016
STDOUT_TEMPLATE='-e "${GREEN}OK${NC}:\t${current_path}\nTO:\t${new_path}\n"'
SYMLINK_ONLY=false
DELETE_METADATA=false
METADATA_EXTENSION="meta"
VERBOSE=false
ORGANIZE_WITHOUT_ISBN=false
DRY_RUN=false
DEBUG_PREFIX_LENGTH=40
VERSION="0.1"

print_help() {
	echo "eBook Organizer v$VERSION"
	echo
	echo "Usage: organize-ebooks.sh [OPTIONS] EBOOK_PATHS..."
	echo
	echo "For information about the possible options, see the beginning of the script itself"
}

for i in "$@"; do
	case $i in
		-o=*|--output-folder=*)
			OUTPUT_FOLDER="${i#*=}"
			if [[ "$OUTPUT_FOLDER_SEPARATE_UNSURE" == false ]]; then
				OUTPUT_FOLDER_UNSURE="${i#*=}"
			fi
		;;
		-ou=*|--output-folder-unsure=*)
			OUTPUT_FOLDER_SEPARATE_UNSURE=true
			OUTPUT_FOLDER_UNSURE="${i#*=}"
		;;
		-ft=*|--filename-template=*) FILENAME_TEMPLATE="${i#*=}" ;;
		-i=*|--isbn-regex=*) ISBN_REGEX="${i#*=}" ;;
		--isbn-direct-grep-files=*) ISBN_DIRECT_GREP_FILES="${i#*=}" ;;
		--isbn-extraction-ignore=*) ISBN_IGNORED_FILES="${i#*=}" ;;
		-owi|--organize--without--isbn) ORGANIZE_WITHOUT_ISBN=true ;;
		-d|--dry-run) DRY_RUN=true ;;
		-sl|--symlink-only) SYMLINK_ONLY=true ;;
		-dm|--delete-metadata) DELETE_METADATA=true ;;
		-me=*|--metadata-extension=*) FILENAME_TEMPLATE="${i#*=}" ;;
		-v|--verbose) VERBOSE=true ;;
		--debug-prefix-length=*) DEBUG_PREFIX_LENGTH="${i#*=}" ;;
		-h|--help) print_help; exit 1 ;;
		-*) echo "Invalid option '$i'"; exit 4; ;;
		*) break ;;
	esac
	shift # past argument=value or argument with no value
done
if [[ "$#" == "0" ]]; then print_help; exit 2; fi


fail_file() {
	#TODO: add a configuration parameter for this
	echo -e "${RED}SKIP${NC}:\t$1\nREASON:\t$2\n"
}

# Arguments:
#	is_sure: whether we are relatively sure of the book metadata accuracy
# 	current_path: the path to book file
#	metadata_path: the path to the metadata file
move_or_link_ebook_file_and_metadata() {
	local current_path
	current_path="$2"
	declare -A d=( ["EXT"]="${current_path##*.}" ) # metadata and the file extension

	while IFS='' read -r line || [[ -n "$line" ]]; do
		d["$(echo "${line%%:*}" | sed -e 's/[ \t]*$//' -e 's/ /_/g' -e 's/[^a-zA-Z0-9_]//g' -e 's/\(.*\)/\U\1/')"]="$(echo "${line#*: }" | sed -e 's/[\\/\*\?<>\|\x01-\x1F\x7F]/_/g' | cut -c 1-120 )"
	done < "$3"

	decho "Variables that will be used for the new filename construction:"
	local key
	for key in "${!d[@]}"; do
		echo "${d[${key}]}" | debug_prefixer "    ${key}" 25
	done

	local new_name
	new_name="$(eval echo "$FILENAME_TEMPLATE")"
	decho "The new file name of the book file/link '$current_path' will be: '$new_name'"

	local new_folder
	if [[ "$1" == true ]]; then
		new_folder="${OUTPUT_FOLDER%/}"
	else
		new_folder="${OUTPUT_FOLDER_UNSURE%/}"
	fi

	local new_path
	new_path="${new_folder}/${new_name}"

	local counter=0
	while [[ -e "$new_path" ]]; do
		counter="$((counter+1))"
		decho "File '$new_path' already exists in destination '${new_folder}', trying with counter $counter!"
		new_path="${new_folder}/${new_name%.*} ($counter).${new_name##*.}"
	done

	eval echo "$STDOUT_TEMPLATE"

	$DRY_RUN && decho "(DRY RUN! All operations except metadata deletion are skipped!)"

	if [[ "$SYMLINK_ONLY" == true ]]; then
		decho "Symlinking file '$current_path' to '$new_path'..."
		$DRY_RUN || ln -s "$(realpath "$current_path")" "$new_path"
	else
		decho "Moving file '$current_path' to '$new_path'..."
		$DRY_RUN || mv --no-clobber "$current_path" "$new_path"
	fi

	if [[ "$DELETE_METADATA" == true ]]; then
		decho "Removing metadata file '$3'..."
		rm "$3"
	else
		decho "Moving metadata file '$3' to '${new_path}.${METADATA_EXTENSION}'..."
		if [[ "$DRY_RUN" != true ]]; then
			mv --no-clobber "$3" "${new_path}.${METADATA_EXTENSION}"
		else
			rm "$3"
		fi
	fi
}

# Sequentially tries to fetch metadata for each of the supplied ISBNs; if any
# is found, writes it to a tmp .txt file and calls organize_known_ebook()
# Arguments: path, isbn (coma-separated)
organize_by_isbns() {
	local tmpmfile
	local isbn

	for isbn in $(echo "$2" | tr ',' '\n'); do
		tmpmfile="$(mktemp --suffix='.txt')"
		decho "Trying to fetch metadata for ISBN '$isbn' into temp file '$tmpmfile'..."
		#TODO: download cover?
		if fetch-ebook-metadata --verbose --isbn="$isbn" 2> >(debug_prefixer "[fetch-meta] " 0 --width=80 -s) | grep -E '[a-zA-Z()]+ +: .*'  > "$tmpmfile"; then
			sleep 0.1
			decho "Successfully fetched metadata: "
			debug_prefixer "[meta] " 0 --width=100 -t < "$tmpmfile"

			decho "Addding additional metadata to the end of the metadata file..."
			{
				echo "ISBN                : $isbn"
				echo "All found ISBNs     : $2"
				echo "Old file path       : $1"
			} >> "$tmpmfile"

			decho "Organizing '$1' (with '$tmpmfile')..."
			move_or_link_ebook_file_and_metadata true "$1" "$tmpmfile"
			return
		fi
		decho "Removing temp file '$tmpmfile'..."
		rm "$tmpmfile"
	done

	if [[ "$ORGANIZE_WITHOUT_ISBN" == true ]]; then
		decho "Could not organize via the found ISBNs, organizing by filename and metadata instead..."
		organize_by_filename_and_meta "$1" "Could not fetch metadata for ISBNs '$2'"
	else
		decho "Organization by filename and metadata is not turned on, giving up..."
		fail_file "$1" "Could not fetch metadata for ISBNs '$2'; Non-ISBN organization not turned on"
	fi
}

# Arguments: filename, reason (optional)
organize_by_filename_and_meta() {
	local old_path
	old_path="$1"

	decho "Organizing '$old_path' by non-ISBN metadata and filename..."

	local ebookmeta
	ebookmeta="$(ebook-meta "$old_path" | grep -E '[a-zA-Z()]+ +: .*' )"
	decho "Ebook metadata:"
	echo "$ebookmeta" | debug_prefixer "	" 0 --width=80 -t

	local title
	title="$(echo "$ebookmeta" | grep '^Title' | awk -F' : ' '{ print $2 }' | sed -E 's/[^[:alnum:]]+/ /g' )"
	local author
	author="$(echo "$ebookmeta" | grep '^Author' | awk -F' : ' '{ print $2 }' | sed -e 's/ & .*//' -e 's/[^[:alnum:]]\+/ /g' )"
	decho "Extracted title '$title' and author '$author'"

	if [[ "${title//[^[:alpha:]]/}" != "" && "$title" != "Unknown" ]]; then
		decho "There is a relatively normal-looking title, searching for metadata..."
		tmpmfile="$(mktemp --suffix='.txt')"
		decho "Created temporary file for metadata downloads '$tmpmfile'"

		finisher() {
			decho "Successfully fetched metadata: "
			debug_prefixer "[meta-$1] " 0 --width=100 -t < "$tmpmfile"
			decho "Addding additional metadata to the end of the metadata file..."
			echo "Old file path       : $old_path">> "$tmpmfile"
			echo "Meta fetch method   : $1">> "$tmpmfile"

			local isbn
			isbn="$(find_isbns < "$tmpmfile")"
			if [[ "$isbn" != "" ]]; then
				echo "ISBN                : $isbn" >> "$tmpmfile"
			fi

			decho "Organizing '$old_path' (with '$tmpmfile')..."
			move_or_link_ebook_file_and_metadata false "$old_path" "$tmpmfile"
		}

		if [[ "${author//[[:space:]]/}" != "" && "$author" != "Unknown" ]]; then
			decho "Trying to fetch metadata by title '$title' and author '$author'..."
			if fetch-ebook-metadata --verbose --title="$title" --author="$author" 2> >(debug_prefixer "[fetch-meta-t&a] " 0 --width=80 -s) | grep -E '[a-zA-Z()]+ +: .*'  > "$tmpmfile"; then
				finisher "title&author"
				return
			fi

			decho "Trying to swap places - author '$title' and title '$author'..."
			if fetch-ebook-metadata --verbose --title="$author" --author="$title" 2> >(debug_prefixer "[fetch-meta-rev-t&a] " 0 --width=80 -s) | grep -E '[a-zA-Z()]+ +: .*'  > "$tmpmfile"; then
				finisher "rev-title&author"
				return
			fi
		fi

		decho "Missing or unknown author, trying to fetch metadata by title '$title'..."
		if fetch-ebook-metadata --verbose --title="$title" --author="$author" 2> >(debug_prefixer "[fetch-meta-t] " 0 --width=80 -s) | grep -E '[a-zA-Z()]+ +: .*'  > "$tmpmfile"; then
			finisher "title"
			return
		fi

		decho "Could not find anything, removing the temp file '$tmpmfile'..."
		rm "$tmpmfile"
	fi

	fail_file "$old_path" "${2:-}${2+; }Insufficient or wrong file name/metadata"
}


organize_file() {
	local isbns
	isbns="$(search_file_for_isbns "$1")"
	if [[ "$isbns" != "" ]]; then
		decho "Organizing '$1' by ISBNs '$isbns'!"
		organize_by_isbns "$1" "$isbns"
	elif [[ "$ORGANIZE_WITHOUT_ISBN" == true ]]; then
		decho "No ISBNs found for '$1', organizing by filename and metadata..."
		organize_by_filename_and_meta "$1" "No ISBNs found"
	else
		fail_file "$1" "No ISBNs found; Non-ISBN organization not turned on"
	fi
	decho "====================================================="
}


for fpath in "$@"; do
	decho "Recursively scanning '$fpath' for files"
	find "$fpath" -type f  -print0 | sort -z | while IFS= read -r -d '' file_to_check
	do
		organize_file "$file_to_check" 2> >(debug_prefixer "[$file_to_check] " "$DEBUG_PREFIX_LENGTH")
	done
done


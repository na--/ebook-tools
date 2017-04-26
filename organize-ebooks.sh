#!/usr/bin/env bash

set -euo pipefail

DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=./lib-org.sh
. "$DIR/lib-org.sh"

DRY_RUN=false
CORRUPTION_CHECK_ONLY=false
SYMLINK_ONLY=false
DELETE_METADATA=false

ORGANIZE_ISBN_META_FETCH_ORDER="Goodreads,Amazon.com,Google,ISBNDB,WorldCat xISBN,OZON.ru" # Requires Calibre 2.84+
ORGANIZE_WITHOUT_ISBN=false
ORGANIZE_WITHOUT_ISBN_IGNORED="$NO_ISBN_IGNORE_REGEX" # Periodicals and images
ORGANIZE_WITHOUT_ISBN_SOURCES="Goodreads,Amazon.com,Google" # Requires Calibre 2.84+, previous versions will search in all enabled sources in the GUI

OUTPUT_FOLDER="$(pwd)"
OUTPUT_FOLDER_SEPARATE_UNSURE=false
OUTPUT_FOLDER_UNSURE="$(pwd)"
OUTPUT_FOLDER_CORRUPT=

VERBOSE=false
DEBUG_PREFIX_LENGTH=40


print_help() {
	echo "eBook Organizer v$VERSION"
	echo
	echo "Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS] EBOOK_PATHS..."
	echo
	echo "For information about the possible options, see the beginning of the script itself"
}

for i in "$@"; do
	case $i in
		-d|--dry-run) DRY_RUN=true ;;
		-sl|--symlink-only) SYMLINK_ONLY=true ;;
		-cco|--corruption-check-only) CORRUPTION_CHECK_ONLY=true ;;
		-dm|--delete-metadata) DELETE_METADATA=true ;;

		-mfo=*|--metadata-fetch-order=*) ORGANIZE_ISBN_META_FETCH_ORDER="${i#*=}" ;;
		-owi|--organize--without--isbn) ORGANIZE_WITHOUT_ISBN=true ;;
		-owii=*|--organize--without--isbn-ignored=*) ORGANIZE_WITHOUT_ISBN_IGNORED="${i#*=}" ;;
		-owis=*|--organize--without--isbn-sources=*) ORGANIZE_WITHOUT_ISBN_SOURCES="${i#*=}" ;;

		-oft=*|--output-filename-template=*) OUTPUT_FILENAME_TEMPLATE="${i#*=}" ;;
		-ome=*|--output-metadata-extension=*) OUTPUT_METADATA_EXTENSION="${i#*=}" ;;
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
		-oc=*|--output-folder-corrupt=*) OUTPUT_FOLDER_CORRUPT="${i#*=}" ;;

		-v|--verbose) VERBOSE=true ;;
		--debug-prefix-length=*) DEBUG_PREFIX_LENGTH="${i#*=}" ;;

		-i=*|--isbn-regex=*) ISBN_REGEX="${i#*=}" ;;
		--isbn-direct-grep-files=*) ISBN_DIRECT_GREP_FILES="${i#*=}" ;;
		--isbn-extraction-ignore=*) ISBN_IGNORED_FILES="${i#*=}" ;;
		--tested-archive-extensions=*) TESTED_ARCHIVE_EXTENSIONS="${i#*=}" ;;
		--reorder-files-for-grep=*)
			i="${i#*=}"
			if [[ "$i" == "false" ]]; then
				ISBN_GREP_REORDER_FILES=false
			else
				ISBN_GREP_REORDER_FILES=true
				ISBN_GREP_RF_SCAN_FIRST="${i%,*}"
				ISBN_GREP_RF_REVERSE_LAST="${i##*,}"
			fi
		;;

		-h|--help) print_help; exit 1 ;;
		-*) echo "Invalid option '$i'"; exit 4; ;;
		*) break ;;
	esac
	shift # past argument=value or argument with no value
done
if [[ "$#" == "0" ]]; then print_help; exit 2; fi


fail_file() {
	echo -e "${RED}ERR${NC}:\t$1\nREASON:\t$2\n${3+TO:\t$3\n}"
}

skip_file() {
	echo -e "SKIP:\t$1\nREASON:\t$2\n"
}

# Arguments: new_folder, current_ebook_path, current_metadata_path
move_or_link_ebook_file_and_metadata() {
	local new_folder="$1" current_ebook_path="$2" current_metadata_path="$3"
	declare -A d=( ["EXT"]="${current_ebook_path##*.}" ) # metadata and the file extension

	while IFS='' read -r line || [[ -n "$line" ]]; do
		d["$(echo "${line%%:*}" | sed -e 's/[ \t]*$//' -e 's/ /_/g' -e 's/[^a-zA-Z0-9_]//g' -e 's/\(.*\)/\U\1/')"]="$(echo "${line#*: }" | sed -e 's/[\\/\*\?<>\|\x01-\x1F\x7F\x22\x24\x60]/_/g' | cut -c 1-110 )"
	done < "$current_metadata_path"

	decho "Variables that will be used for the new filename construction:"
	local key
	for key in "${!d[@]}"; do
		echo "${d[${key}]}" | debug_prefixer "    ${key}" 25
	done

	local new_name
	new_name="$(eval echo "$OUTPUT_FILENAME_TEMPLATE")"
	decho "The new file name of the book file/link '$current_ebook_path' will be: '$new_name'"

	local new_path
	new_path="$(unique_filename "${new_folder%/}" "$new_name")"
	echo -e "${GREEN}OK${NC}:\t${current_ebook_path}\nTO:\t${new_path}\n"

	$DRY_RUN && decho "(DRY RUN! All operations except metadata deletion are skipped!)"
	if [[ "$SYMLINK_ONLY" == true ]]; then
		decho "Symlinking file '$current_ebook_path' to '$new_path'..."
		$DRY_RUN || ln -s "$(realpath "$current_ebook_path")" "$new_path"
	else
		decho "Moving file '$current_ebook_path' to '$new_path'..."
		$DRY_RUN || mv --no-clobber "$current_ebook_path" "$new_path"
	fi

	if [[ "$DELETE_METADATA" == true ]]; then
		decho "Removing metadata file '$current_metadata_path'..."
		rm "$current_metadata_path"
	else
		decho "Moving metadata file '$current_metadata_path' to '${new_path}.${OUTPUT_METADATA_EXTENSION}'..."
		if [[ "$DRY_RUN" != true ]]; then
			mv --no-clobber "$current_metadata_path" "${new_path}.${OUTPUT_METADATA_EXTENSION}"
		else
			rm "$current_metadata_path"
		fi
	fi
}




# Uses Calibre's fetch-ebook-metadata CLI tool to download metadata from
# online sources. The first parameter is the debug prefix, the second is the
# coma-separated list of allowed plugins and the rest are passed directly
# to fetch-ebook-metadata
fetch_metadata() {
	local isbn_sources
	IFS=, read -ra isbn_sources <<< "$2"

	local isbn_source="" args=()
	for isbn_source in "${isbn_sources[@]:-}"; do
		args+=("${isbn_source:+--allowed-plugin=$isbn_source}")
	done

	decho "Calling fetch-ebook-metadata --verbose" "${args[*]}" "${@:3}"
	fetch-ebook-metadata --verbose "${args[@]}" "${@:3}" 2> >(debug_prefixer "[$1] " 0 --width=100 -s) | grep -E '[a-zA-Z()]+ +: .*'
}

# Sequentially tries to fetch metadata for each of the supplied ISBNs; if any
# is found, writes it to a tmp .txt file and calls organize_known_ebook()
# Arguments: path, isbn (coma-separated)
organize_by_isbns() {
	local isbn_sources
	IFS=, read -ra isbn_sources <<< "$ORGANIZE_ISBN_META_FETCH_ORDER"

	local isbn
	for isbn in $(echo "$2" | tr "$ISBN_RET_SEPARATOR" '\n'); do
		local tmpmfile
		tmpmfile="$(mktemp --suffix='.txt')"
		decho "Trying to fetch metadata for ISBN '$isbn' into temp file '$tmpmfile'..."

		local isbn_source
		for isbn_source in "${isbn_sources[@]:-}"; do
			decho "Fetching metadata from ${isbn_source:-all sources}..."
			if fetch_metadata "fetch-meta-${isbn_source:-all}" "${isbn_source:-}" --isbn="$isbn" > "$tmpmfile"; then
				sleep 0.1
				decho "Successfully fetched metadata: "
				debug_prefixer "[meta] " 0 --width=100 -t < "$tmpmfile"

				decho "Addding additional metadata to the end of the metadata file..."
				{
					echo "ISBN                : $isbn"
					echo "All found ISBNs     : $2"
					echo "Old file path       : $1"
					echo "Metadata source     : $isbn_source"
				} >> "$tmpmfile"

				decho "Organizing '$1' (with '$tmpmfile')..."
				move_or_link_ebook_file_and_metadata "$OUTPUT_FOLDER" "$1" "$tmpmfile"
				return
			fi
		done

		decho "Removing temp file '$tmpmfile'..."
		rm "$tmpmfile"
	done

	if [[ "$ORGANIZE_WITHOUT_ISBN" == true ]]; then
		decho "Could not organize via the found ISBNs, organizing by filename and metadata instead..."
		organize_by_filename_and_meta "$1" "Could not fetch metadata for ISBNs '$2'"
	else
		decho "Organization by filename and metadata is not turned on, giving up..."
		skip_file "$1" "Could not fetch metadata for ISBNs '$2'; Non-ISBN organization not turned on"
	fi
}

# Arguments: filename, reason (optional)
organize_by_filename_and_meta() {
	local old_path
	old_path="$1"

	decho "Organizing '$old_path' by non-ISBN metadata and filename..."

	local lowercase_name
	lowercase_name="$(basename "$old_path" | sed -E 's/[[:upper:]]+/\L&/g')"
	if [[ "$lowercase_name" =~ $ORGANIZE_WITHOUT_ISBN_IGNORED ]]; then
		local matches
		matches="[$(echo "$lowercase_name" | grep -oE "$NO_ISBN_IGNORE_REGEX" | paste -sd';')]"
		decho "Parts of the filename match the ignore regex: [$matches]"
		skip_file "$old_path" "${2:-}${2+; }File matches the ignore regex ($matches)"
		return
	else
		decho "File does not match the ignore regex, continuing..."
	fi

	local ebookmeta
	ebookmeta="$(ebook-meta "$old_path" | grep -E '[a-zA-Z()]+ +: .*' )"
	decho "Ebook metadata:"
	echo "$ebookmeta" | debug_prefixer "	" 0 --width=80 -t

	tmpmfile="$(mktemp --suffix='.txt')"
	decho "Created temporary file for metadata downloads '$tmpmfile'"

	local title
	title="$(echo "$ebookmeta" | grep_meta_val "Title" | sed -E 's/[^[:alnum:]]+/ /g' )"
	local author
	author="$(echo "$ebookmeta" | grep_meta_val "Author" | sed -e 's/ & .*//' -e 's/[^[:alnum:]]\+/ /g' )"
	decho "Extracted title '$title' and author '$author'"

	if [[ "${title//[^[:alpha:]]/}" != "" && "$title" != "Unknown" ]]; then
		decho "There is a relatively normal-looking title, searching for metadata..."

		finisher() {
			decho "Successfully fetched metadata: "
			debug_prefixer "[meta-$1] " 0 --width=100 -t < "$tmpmfile"
			decho "Addding additional metadata to the end of the metadata file..."
			{
				echo "Old file path       : $old_path" >> "$tmpmfile"
				echo "Meta fetch method   : $1" >> "$tmpmfile"
				echo "$ebookmeta" | sed -E 's/^(.+[^ ])   ([ ]+): /OF \1\2: /'
			} >> "$tmpmfile"

			local isbn
			isbn="$(find_isbns < "$tmpmfile")"
			if [[ "$isbn" != "" ]]; then
				echo "ISBN                : $isbn" >> "$tmpmfile"
			fi

			decho "Organizing '$old_path' (with '$tmpmfile')..."
			move_or_link_ebook_file_and_metadata "$OUTPUT_FOLDER_UNSURE" "$old_path" "$tmpmfile"
		}

		if [[ "${author//[[:space:]]/}" != "" && "$author" != "Unknown" ]]; then
			decho "Trying to fetch metadata by title '$title' and author '$author'..."
			if fetch_metadata "fetch-meta-title&author" "$ORGANIZE_WITHOUT_ISBN_SOURCES" --title="$title" --author="$author" > "$tmpmfile"; then
				finisher "title&author"
				return
			fi
			decho "Trying to swap places - author '$title' and title '$author'..."
			if fetch_metadata "fetch-meta-rev-title&author" "$ORGANIZE_WITHOUT_ISBN_SOURCES" --title="$author" --author="$title" > "$tmpmfile"; then
				finisher "rev-title&author"
				return
			fi
		fi

		decho "Trying to fetch metadata only by title '$title'..."
		if fetch_metadata "fetch-meta-title" "$ORGANIZE_WITHOUT_ISBN_SOURCES" --title="$title" > "$tmpmfile"; then
			finisher "title"
			return
		fi
	fi

	local filename
	filename="$(basename "${old_path%.*}" | sed -E 's/[^[:alnum:]]+/ /g')"

	decho "Trying to fetch metadata only the filename '$filename'..."
	if fetch_metadata "fetch-meta-filename" "$ORGANIZE_WITHOUT_ISBN_SOURCES" --title="$filename" > "$tmpmfile"; then
		finisher "filename"
		return
	fi

	decho "Could not find anything, removing the temp file '$tmpmfile'..."
	rm "$tmpmfile"

	skip_file "$old_path" "${2:-}${2+; }Insufficient or wrong file name/metadata"
}


organize_file() {
	local file_err
	file_err="$(check_file_for_corruption "$1")"
	if [[ "$file_err" != "" ]]; then
		decho "File '$1' is corrupt with error '$file_err'"
		if [[ "${OUTPUT_FOLDER_CORRUPT%/}" != "" ]]; then
			local new_path
			new_path="$(unique_filename "${OUTPUT_FOLDER_CORRUPT%/}" "$(basename "$1")")"

			fail_file "$1" "File is corrupt: $file_err" "$new_path"

			$DRY_RUN && decho "(DRY RUN! All operations except metadata deletion are skipped!)"
			if [[ "$SYMLINK_ONLY" == true ]]; then
				decho "Symlinking file '$1' to '$new_path'..."
				$DRY_RUN || ln -s "$(realpath "$1")" "$new_path"
			else
				decho "Moving file '$1' to '$new_path'..."
				$DRY_RUN || mv --no-clobber "$1" "$new_path"
			fi

			local new_metadata_path="${new_path}.${OUTPUT_METADATA_EXTENSION}"
			decho "Saving original filename to '$new_metadata_path'..."
			$DRY_RUN || echo "Corruption reason   : $file_err" >> "$new_metadata_path"
			$DRY_RUN || echo "Old file path       : $1" >> "$new_metadata_path"
		else
			decho "Output folder for corrupt files is not set, doing nothing"
			fail_file "$1" "File is corrupt: $file_err"
		fi
	elif [[ "$CORRUPTION_CHECK_ONLY" == true ]]; then
		decho "We are only checking for corruption, do not continue organising..."
		skip_file "$1" "File appears OK"
	else
		decho "File passed the corruption test, looking for ISBNs..."

		local isbns
		isbns="$(search_file_for_isbns "$1")"
		if [[ "$isbns" != "" ]]; then
			decho "Organizing '$1' by ISBNs '$isbns'!"
			organize_by_isbns "$1" "$isbns"
		elif [[ "$ORGANIZE_WITHOUT_ISBN" == true ]]; then
			decho "No ISBNs found for '$1', organizing by filename and metadata..."
			organize_by_filename_and_meta "$1" "No ISBNs found"
		else
			skip_file "$1" "No ISBNs found; Non-ISBN organization not turned on"
		fi
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


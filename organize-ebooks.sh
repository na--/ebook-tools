#!/usr/bin/env bash

set -euo pipefail

OUTPUT_FOLDER="$(pwd)"
OUTPUT_FOLDER_SEPARATE_UNSURE=false
OUTPUT_FOLDER_UNSURE="$(pwd)"
ISBN_REGEX='\b(978|979)?(([ -]?[0-9][ -]?){9}[0-9xX])\b'
ISBN_DIRECT_GREP_FILES='^text/(plain|xml|html)$'
ISBN_IGNORED_FILES='^image/(png|jpeg|gif)$'
#shellcheck disable=SC2016
FILENAME_TEMPLATE='"${d[AUTHORS]/ & /, } - ${d[SERIES]+[${d[SERIES]}] - }${d[TITLE]/:/ -} ${d[PUBLISHED]+(${d[PUBLISHED]%%-*}) }[${d[ISBN]}].${d[EXT]}"'
#shellcheck disable=SC2016
STDOUT_TEMPLATE='-e "from:\t${current_path}\nto:\t${new_name}\n"'
SYMLINK_ONLY=false
DELETE_METADATA=false
METADATA_EXTENSION="meta"
FORCE_OVERWRITE=false
VERBOSE=false
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
		-d|--dry-run) DRY_RUN=true ;;
		-sl|--symlink-only) SYMLINK_ONLY=true ;;
		-dm|--delete-metadata) DELETE_METADATA=true ;;
		-me=*|--metadata-extension=*) FILENAME_TEMPLATE="${i#*=}" ;;
		-f|--force) FORCE_OVERWRITE=true ;;
		-v|--verbose) VERBOSE=true ;;
		--debug-prefix-length=*) DEBUG_PREFIX_LENGTH="${i#*=}" ;;
		-h|--help) print_help; exit 1 ;;
		-*) echo "Invalid option '$i'"; exit 4; ;;
		*) break ;;
	esac
	shift # past argument=value or argument with no value
done
if [[ "$#" == "0" ]]; then print_help; exit 2; fi


# If the VERBOSE flag is on, outputs the arguments to stderr
decho () {
	if [[ "$VERBOSE" == true ]]; then
		echo "$@" >&2
	fi
}

# If the VERBOSE flag is on, prefixes the stdin with the supplied prefix
# (shortened/padded or not) and outputs the result to stderr
#
# Arguments:
#	prefix:	the string with which we will prefix the lines
#	[should_fit_in]: number of characters to which we want to shorten or pad
#		the prefix so it fits; 0 is disabled
#	[...]: everything else is passed to the fmt command
debug_prefixer() {
	local prefix
	prefix="$1"
	if [[ "$#" -gt 1 ]]; then
		if [[ "$2" -gt 0 ]]; then
			if (( ${#1} > $2 )); then
				prefix="${1:0:10}..${1:(-$(($2-12)))}"
			else
				prefix="$(printf "%-${2}s" "$1")"
			fi
		fi
		shift
	fi
	shift

	( if [[ "$#" != "0" ]]; then fmt "$@"; else cat; fi ) |
	while IFS= read -r line || [[ -n "$line" ]] ; do
		decho "${prefix}${line}"
	done
}


# Validates ISBN-10 and ISBN-13 numbers
is_isbn_valid() {
	local isbn
	isbn="$(echo "$1" | tr -d ' -' | tr '[:lower:]' '[:upper:]')"
	local sum=0

	if [ "${#isbn}" == "10" ]; then
		local number
		for i in {0..9}; do
			number="${isbn:$i:1}"
			if [[ "$i" == "9" && "$number" == "X" ]]; then
				number=10
			fi
			let "sum = $sum + ($number * ( 10 - $i ))"
		done
		if [ "$((sum % 11))" == "0" ]; then
			return 0
		fi
	elif [ "${#isbn}" == "13" ]; then
		if [[ "${isbn:0:3}" = "978" || "${isbn:0:3}" = "979" ]]; then
			for i in {0..12..2}; do
				let "sum = $sum + ${isbn:$i:1}"
			done
			for i in {1..11..2}; do
				let "sum = $sum + (${isbn:$i:1} * 3)"
			done
			if [ "$((sum % 10))" == "0" ]; then
				return 0
			fi
		fi
	fi
	return 1
}


# Searches STDIN for ISBN-like sequences and removes duplicates (preserving
# the order) and finally validates them using is_isbn_valid() and returns
# them coma-separated
find_isbns() {
	{ grep -oE "$ISBN_REGEX" || true; } | tr -d ' -' | awk '!x[$0]++' | (
		while IFS='' read -r isbn || [[ -n "$isbn" ]]; do
			if is_isbn_valid "$isbn"; then
				echo "$isbn"
			fi
		done
	) | paste -sd "," -
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
		d["$(echo "${line%%:*}" | sed -e 's/[ \t]*$//' -e 's/ /_/g' -e 's/[^a-zA-Z0-9_]//g' -e 's/\(.*\)/\U\1/')"]="$(echo "${line#*: }" | sed -e 's/[\\/\*\?<>\|\x01-\x1F\x7F]/_/g' )"
	done < "$3"

	decho "Variables that will be used for the new filename construction:"
	local key
	for key in "${!d[@]}"; do
		echo "${d[${key}]}" | debug_prefixer "    ${key}" 25
	done

	local new_name
	new_name="$(eval echo "$FILENAME_TEMPLATE")"
	decho "The new file name of the book file/link '$current_path' will be: '$new_name'"

	local new_path
	if [[ "$1" == true ]]; then
		new_path="$OUTPUT_FOLDER/$new_name"
	else
		new_path="$OUTPUT_FOLDER_UNSURE/$new_name"
	fi

	eval echo "$STDOUT_TEMPLATE"

	if [[ -e "$new_path" ]]; then
		if [[ "$FORCE_OVERWRITE" == true ]]; then
			decho "File '$new_path' already exists and force overwrite is enabled, overwriting!"
		else
			decho "ERROR: file '$new_path' already exists and force overwrite is disabled!"
			echo "ERROR: file '$new_path' already exists and force overwrite is disabled!"
			exit 3
		fi
	fi

	$DRY_RUN && decho "(DRY RUN! All operations except metadata deletion are skipped!)"

	if [[ "$SYMLINK_ONLY" == true ]]; then
		decho "Symlinking file '$current_path' to '$new_path'..."
		$DRY_RUN || ln -s "$(realpath "$current_path")" "$new_path"
	else
		decho "Moving file '$current_path' to '$new_path'..."
		$DRY_RUN || mv "$current_path" "$new_path"
	fi

	if [[ "$DELETE_METADATA" == true ]]; then
		decho "Removing metadata file '$3'..."
		rm "$3"
	else
		decho "Moving metadata file '$3' to '${new_path}.${METADATA_EXTENSION}'..."
		if [[ "$DRY_RUN" == true ]]; then
			rm "$3"
		else
			mv "$3" "${new_path}.${METADATA_EXTENSION}"
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
			return 0
		fi
		decho "Removing temp file '$tmpmfile'..."
		rm "$tmpmfile"
	done
	return 1
}

# Arguments: filename
organize_by_filename_and_meta() {
	decho "TODO: organizing ebook $1 by the filename and metadata! TODO split filename into words, extract metadata stuff if present try to get the opf from the filename, but move it to a 'to check' folder if successful"
	echo -e "SKIP:\t$1\n"
}


# Tries to convert the supplied ebook file into .txt. It uses calibre's
# ebook-convert tool. For optimization, if present, it will use pdftotext
# for pdfs.
# Arguments: input path, output path (shloud have .txt extension), mimetype
convert_to_txt() {
	if [[ "$3" == "application/pdf" ]] && command -v pdftotext >/dev/null 2>&1; then
		pdftotext "$1" "$2"
	else
		ebook-convert "$1" "$2"
	fi
}

search_file_for_isbns() {
	decho "Searching file '$1' for ISBN numbers..."
	local isbns

	isbns="$(echo "$1" | find_isbns)"
	if [[ "$isbns" != "" ]]; then
		decho "Extracted ISBNs '$isbns' from filename!"
		echo -n "$isbns"
		return
	fi

	local mimetype
	mimetype="$(file --brief --mime-type "$1")"
	decho "Ebook MIME type: $mimetype"
	if [[ "$mimetype" =~ $ISBN_DIRECT_GREP_FILES ]]; then
		decho "Ebook is in text format, trying to find ISBN directly"
		isbns="$(find_isbns < "$1")"
		if [[ "$isbns" != "" ]]; then
			decho "Extracted ISBNs '$isbns' from the text file contents!"
			echo -n "$isbns"
		else
			decho "Did not find any ISBNs"
		fi
		return
	elif [[ "$mimetype" =~ $ISBN_IGNORED_FILES ]]; then
		decho "The file is an image, ignoring..."
		return
	fi


	local ebookmeta
	ebookmeta="$(ebook-meta "$1")"
	decho "Ebook metadata:"
	echo "$ebookmeta" | debug_prefixer "	" 0 --width=80 -t
	isbns="$(echo "$ebookmeta" | find_isbns)"
	if [[ "$isbns" != "" ]]; then
		decho "Extracted ISBNs '$isbns' from calibre ebook metadata!"
		echo -n "$isbns"
		return
	fi


	decho "Trying to decompress the ebook and recursively scan the contents"
	local tmpdir
	tmpdir="$(mktemp -d)"
	decho "Created a temporary folder '$tmpdir'"
	if 7z x -o"$tmpdir" "$1" 2>&1 | debug_prefixer "[7zx] " 0 --width=80 -s; then
		decho "Archive extracted successfully in $tmpdir, scanning contents recursively..."
		while IFS= read -r -d '' file_to_check; do
			#decho "Searching '$file_to_check' for ISBNs..."
			isbns="$(search_file_for_isbns "$file_to_check" 2> >(debug_prefixer "[${file_to_check#$tmpdir}] " "$DEBUG_PREFIX_LENGTH") )"
			if [[ "$isbns" != "" ]]; then
				decho "Found ISBNs $isbns!"
				echo -n "$isbns"
				decho "Removing temporary folder '$tmpdir'..."
				rm -rf "$tmpdir"
				return
			fi
		done < <(find "$tmpdir" -type f  -print0 | sort -z)
	else
		decho "Error extracting the file (probably not an archive)"
	fi
	decho "Removing temporary folder '$tmpdir'..."
	rm -rf "$tmpdir"


	local tmptxtfile
	tmptxtfile="$(mktemp --suffix='.txt')"
	decho "Converting ebook to text format in file '$tmptxtfile'..."
	if convert_to_txt "$1" "$tmptxtfile" "$mimetype" 2>&1 | debug_prefixer "[ebook2txt] " 0 --width=80 -s; then
		decho "Conversion is done, trying to find ISBNs in the text output..."
		isbns="$(find_isbns < "$tmptxtfile")"
		if [[ "$isbns" != "" ]]; then
			decho "Extracted ISBNs '$isbns' directly from the converted text output!"
			echo -n "$isbns"
			decho "Removing '$tmptxtfile'..."
			rm "$tmptxtfile"
			return
		else
			decho "Did not find any ISBNs"
		fi
	else
		decho "There was an error converting the book to txt format"
	fi
	decho "Removing '$tmptxtfile'..."
	rm "$tmptxtfile"

	decho "Could not find any ISBNs in '$1' :("
}

organize_file() {
	local isbns
	isbns="$(search_file_for_isbns "$1")"
	if [[ "$isbns" != "" ]]; then
		decho "Organizing '$1' by ISBNs '$isbns'!"
		if ! organize_by_isbns "$1" "$isbns"; then
			decho "Could not organize via the found ISBNs, organizing by filename and metadata instead..."
			organize_by_filename_and_meta "$1"
		fi
	else
		decho "No ISBNs found for '$1', organizing by filename and metadata..."
		organize_by_filename_and_meta "$1"
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


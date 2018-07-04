#!/usr/bin/env bash

set -eEuo pipefail

: "${CORRUPTION_CHECK_ONLY:=false}"
: "${ORGANIZE_WITHOUT_ISBN:=false}"

: "${OUTPUT_FOLDER:="$(pwd)"}"
: "${OUTPUT_FOLDER_UNCERTAIN:=}"
: "${OUTPUT_FOLDER_CORRUPT:=}"
: "${OUTPUT_FOLDER_PAMPHLETS:=}"

: "${PAMPHLET_INCLUDED_FILES:="\\.(png|jpg|jpeg|gif|bmp|svg|csv|pptx?)\$"}"
: "${PAMPHLET_EXCLUDED_FILES:="\\.(chm|epub|cbr|cbz|mobi|lit|pdb)\$"}"
: "${PAMPHLET_MAX_PDF_PAGES:=50}"
: "${PAMPHLET_MAX_FILESIZE_KB:=250}"

# shellcheck source=./lib.sh
. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib.sh"

print_help() {
	echo "eBook Organizer v$VERSION"
	echo
	echo "Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS] EBOOK_FOLDERS..."
	echo
	echo "For information about the possible options, see the README.md file or the script source itself"
}

for arg in "$@"; do
	case "$arg" in
		-cco|--corruption-check-only) CORRUPTION_CHECK_ONLY=true ;;
		-owi|--organize-without-isbn) ORGANIZE_WITHOUT_ISBN=true ;;

		-o=*|--output-folder=*) OUTPUT_FOLDER="${arg#*=}" ;;
		-ofu=*|--output-folder-uncertain=*) OUTPUT_FOLDER_UNCERTAIN="${arg#*=}" ;;
		-ofc=*|--output-folder-corrupt=*) OUTPUT_FOLDER_CORRUPT="${arg#*=}" ;;
		-ofp=*|--output-folder-pamphlets=*) OUTPUT_FOLDER_PAMPHLETS="${arg#*=}" ;;

		--pamphlet-included-files=*) PAMPHLET_INCLUDED_FILES="${arg#*=}" ;;
		--pamphlet-excluded-files=*) PAMPHLET_EXCLUDED_FILES="${arg#*=}" ;;
		--pamphlet-max-pdf-pages=*) PAMPHLET_MAX_PDF_PAGES="${arg#*=}" ;;
		--pamphlet-max-filesize-kb=*) PAMPHLET_MAX_FILESIZE_KB="${arg#*=}" ;;

		-h|--help) print_help; exit 1 ;;
		-*) handle_script_arg "$arg" ;;
		*) break ;;
	esac
	shift # past argument=value or argument with no value
done
unset -v arg
if [[ "$#" == "0" ]]; then print_help; exit 2; fi


fail_file() {
	echo -e "${RED}ERR${NC}:\\t$1\\nREASON:\\t$2\\n${3+TO:\\t$3\\n}"
}

ok_file() {
	echo -e "${GREEN}OK${NC}:\\t${1}\\nTO:\\t${2}\\n"
}

skip_file() {
	echo -e "SKIP:\\t$1\\nREASON:\\t$2\\n"
}

# Arguments: path
is_pamphlet() {
	local file_path="$1" lowercase_name

	decho "Checking whether '$file_path' looks like a pamphlet..."
	lowercase_name="$(basename "$file_path" | to_lower)"

	if [[ "$lowercase_name" =~ $PAMPHLET_INCLUDED_FILES ]]; then
		decho "Parts of the filename match the pamphlet include regex: [$(echo "$lowercase_name" | grep -oE "$PAMPHLET_INCLUDED_FILES" | paste -sd';')]"
		return 0
	fi
	decho "The file does not match the pamphlet include regex, continuing..."

	if [[ "$lowercase_name" =~ $PAMPHLET_EXCLUDED_FILES ]]; then
		decho "Parts of the filename match the pamphlet ignore regex: [$(echo "$lowercase_name" | grep -oE "$PAMPHLET_EXCLUDED_FILES" | paste -sd';')]"
		return 1
	fi
	decho "The file does not match the pamphlet exclude regex, continuing..."

	local mimetype filesize_kb pages
	mimetype=$(file --brief --mime-type "$file_path")
	filesize_kb=$(( $(stat -c '%s' "$file_path") / 1024 ))
	if [[ "$mimetype" == "application/pdf" ]]; then
		decho "The file looks like a pdf, checking if the number of pages is larger than $PAMPHLET_MAX_PDF_PAGES ..."
		pages=$(pdfinfo "$file_path" | sed -n -E 's/^Pages:\s+([0-9]+)/\1/p')

		if (( pages > PAMPHLET_MAX_PDF_PAGES )); then
			decho "The file has $pages pages, too many for a pamphlet"
			return 2
		else
			decho "The file has only $pages pages, looks like a pamphlet"
			return 0
		fi
	elif (( filesize_kb < PAMPHLET_MAX_FILESIZE_KB )); then
		decho "File has a type '$mimetype' and a small size ($filesize_kb KB), looks like a pamphlet"
		return 0
	else
		decho "File has a type '$mimetype' and a large size ($filesize_kb KB), does NOT look like a pamphlet"
		return 3
	fi
}


# Sequentially tries to fetch metadata for each of the supplied ISBNs; if any
# is found, writes it to a tmp .txt file and calls organize_known_ebook()
# Arguments: path, isbns (coma-separated)
organize_by_isbns() {
	local file_path="$1" isbns="$2" isbn isbn_sources isbn_source tmpmfile new_path
	IFS=, read -ra isbn_sources <<< "$ISBN_METADATA_FETCH_ORDER"

	for isbn in $(echo "$isbns" | tr "$ISBN_RET_SEPARATOR" '\n'); do
		tmpmfile="$(mktemp --suffix='.txt')"
		decho "Trying to fetch metadata for ISBN '$isbn' into temp file '$tmpmfile'..."

		for isbn_source in "${isbn_sources[@]:-}"; do
			decho "Fetching metadata from ${isbn_source:-all sources}..."
			if fetch_metadata "fetch-meta-${isbn_source:-all}" "${isbn_source:-}" --isbn="$isbn" > "$tmpmfile"; then
				sleep 0.1
				decho "Successfully fetched metadata: "
				debug_prefixer "[meta] " 0 --width=100 -t < "$tmpmfile"

				decho "Addding additional metadata to the end of the metadata file..."
				{
					echo "ISBN                : $isbn"
					echo "All found ISBNs     : $isbns"
					echo "Old file path       : $file_path"
					echo "Metadata source     : $isbn_source"
				} >> "$tmpmfile"

				decho "Organizing '$file_path' (with '$tmpmfile')..."
				new_path="$(move_or_link_ebook_file_and_metadata "$OUTPUT_FOLDER" "$file_path" "$tmpmfile")"
				ok_file "$file_path" "$new_path"
				return
			fi
		done

		decho "Removing temp file '$tmpmfile'..."
		rm "$tmpmfile"
	done

	if [[ "$ORGANIZE_WITHOUT_ISBN" == true ]]; then
		decho "Could not organize via the found ISBNs, organizing by filename and metadata instead..."
		organize_by_filename_and_meta "$file_path" "Could not fetch metadata for ISBNs '$isbns'"
	else
		decho "Organization by filename and metadata is not turned on, giving up..."
		skip_file "$file_path" "Could not fetch metadata for ISBNs '$isbns'; Non-ISBN organization disabled"
	fi
}

# Arguments: path, reason (optional)
organize_by_filename_and_meta() {
	local old_path="$1" prev_reason="${2:-}${2+; }"
	decho "Organizing '$old_path' by non-ISBN metadata and filename..."
	local lowercase_name
	lowercase_name="$(basename "$old_path" | to_lower)"
	if [[ "$WITHOUT_ISBN_IGNORE" != "" && "$lowercase_name" =~ $WITHOUT_ISBN_IGNORE ]]; then
		local matches
		matches="[$(echo "$lowercase_name" | grep -oE "$WITHOUT_ISBN_IGNORE" | paste -sd';')]"
		decho "Parts of the filename match the ignore regex: [$matches]"
		skip_file "$old_path" "${prev_reason}File matches the ignore regex ($matches)"
		return
	else
		decho "File does not match the ignore regex, continuing..."
	fi

	if is_pamphlet "$old_path"; then
		decho "File '$old_path' looks like a pamphlet!"
		if [[ "${OUTPUT_FOLDER_PAMPHLETS%/}" != "" ]]; then
			local new_path
			new_path="$(unique_filename "${OUTPUT_FOLDER_PAMPHLETS%/}/$(dirname "$old_path")" "$(basename "$old_path")")"

			decho "Moving file '$old_path' to '$new_path'!"
			ok_file "$old_path" "$new_path"

			move_or_link_file "$old_path" "$new_path"
		else
			decho "Output folder for pamphlet files is not set, skipping..."
			skip_file "$old_path" "No pamphlet folder specified"
		fi
		return
	fi

	if [[ "${OUTPUT_FOLDER_UNCERTAIN%/}" == "" ]]; then
		decho "No uncertain folder specified, skipping..."
		skip_file "$old_path" "No uncertain folder specified"
		return
	fi

	local ebookmeta
	ebookmeta=$(ebook-meta "$old_path" | grep -E '[a-zA-Z()]+ +: .*') #'
	decho "Ebook metadata:"
	echo "$ebookmeta" | debug_prefixer "	" 0 --width=80 -t

	tmpmfile="$(mktemp --suffix='.txt')"
	decho "Created temporary file for metadata downloads '$tmpmfile'"

	finisher() {
		local fetch_method="$1"
		decho "Successfully fetched metadata: "
		debug_prefixer "[meta-$fetch_method] " 0 --width=100 -t < "$tmpmfile"
		decho "Addding additional metadata to the end of the metadata file..."
		{
			echo "Old file path       : $old_path" >> "$tmpmfile"
			echo "Meta fetch method   : $fetch_method" >> "$tmpmfile"
			echo "$ebookmeta" | sed -E 's/^(.+[^ ])   ([ ]+): /OF \1\2: /'
		} >> "$tmpmfile"

		local isbn new_path
		isbn="$(find_isbns < "$tmpmfile")"
		if [[ "$isbn" != "" ]]; then
			echo "ISBN                : $isbn" >> "$tmpmfile"
		fi

		decho "Organizing '$old_path' (with '$tmpmfile')..."
		new_path="$(move_or_link_ebook_file_and_metadata "$OUTPUT_FOLDER_UNCERTAIN" "$old_path" "$tmpmfile")"
		ok_file "$old_path" "$new_path"
	}

	local title author
	title="$(echo "$ebookmeta" | grep_meta_val "Title" | tokenize ' ' false)"
	author="$(echo "$ebookmeta" | grep_meta_val "Author" | sed -e 's/ & .*//' | tokenize ' ' true)"
	decho "Extracted title '$title' and author '$author'"
	if [[ "${title//[^[:alpha:]]/}" != "" && "$title" != "unknown" ]]; then
		decho "There is a relatively normal-looking title, searching for metadata..."

		if [[ "${author//[[:space:]]/}" != "" && "$author" != "unknown" ]]; then
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
	filename="$(basename "${old_path%.*}" | tokenize)"
	decho "Trying to fetch metadata only the filename '$filename'..."
	if fetch_metadata "fetch-meta-filename" "$ORGANIZE_WITHOUT_ISBN_SOURCES" --title="$filename" > "$tmpmfile"; then
		finisher "filename"
		return
	fi

	decho "Could not find anything, removing the temp file '$tmpmfile'..."
	rm "$tmpmfile"

	skip_file "$old_path" "${prev_reason}Insufficient or wrong file name/metadata"
}


organize_file() {
	local file_path="$1" file_err
	file_err="$(check_file_for_corruption "$file_path")"
	if [[ "$file_err" != "" ]]; then
		decho "File '$file_path' is corrupt with error '$file_err'"
		if [[ "${OUTPUT_FOLDER_CORRUPT%/}" != "" ]]; then
			local new_path
			new_path="$(unique_filename "${OUTPUT_FOLDER_CORRUPT%/}" "$(basename "$file_path")")"

			fail_file "$file_path" "File is corrupt: $file_err" "$new_path"

			move_or_link_file "$file_path" "$new_path"

			local new_metadata_path="${new_path}.${OUTPUT_METADATA_EXTENSION}"
			decho "Saving original filename to '$new_metadata_path'..."
			if [[ "$DRY_RUN" == "false" ]]; then
				echo "Corruption reason   : $file_err" >> "$new_metadata_path"
				echo "Old file path       : $file_path" >> "$new_metadata_path"
			fi
		else
			decho "Output folder for corrupt files is not set, doing nothing"
			fail_file "$file_path" "File is corrupt: $file_err"
		fi
	elif [[ "$CORRUPTION_CHECK_ONLY" == true ]]; then
		decho "We are only checking for corruption, do not continue organising..."
		skip_file "$file_path" "File appears OK"
	else
		decho "File passed the corruption test, looking for ISBNs..."

		local isbns
		isbns="$(search_file_for_isbns "$file_path")"
		if [[ "$isbns" != "" ]]; then
			decho "Organizing '$file_path' by ISBNs '$isbns'!"
			organize_by_isbns "$file_path" "$isbns"
		elif [[ "$ORGANIZE_WITHOUT_ISBN" == true ]]; then
			decho "No ISBNs found for '$file_path', organizing by filename and metadata..."
			organize_by_filename_and_meta "$file_path" "No ISBNs found"
		else
			skip_file "$file_path" "No ISBNs found; Non-ISBN organization disabled"
		fi
	fi
	decho "====================================================="
}


for fpath in "$@"; do
	decho "Recursively scanning '$fpath' for files"
	find "$fpath" -type f  -print0 | sort -z ${FILE_SORT_FLAGS[@]:+"${FILE_SORT_FLAGS[@]}"} | while IFS= read -r -d '' file_to_check
	do
		organize_file "$file_to_check" 2> >(debug_prefixer "[$file_to_check] " "$DEBUG_PREFIX_LENGTH")
	done
done

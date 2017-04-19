#!/bin/bash

set -euo pipefail

VERBOSE=1
ISBN_DIRECT_GREP_FILES='^text/(plain|xml|html)$'
ISBN_IGNORED_FILES='^image/(png|jpeg|gif)$'

decho () {
	if [[ "$VERBOSE" == "1" ]]; then
		echo "$@" >&2
	fi
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


# Searches STDIN for ISBN-like sequences, removes duplicates, sorts them by
# longest first (so ISBN-13 numbers are first), validates them using
# is_isbn_valid() and returns them coma-separated
find_isbns() {
	{ grep -oE '\b(978|979)?(([ -]?[0-9][ -]?){9}[0-9xX])\b' || true; } | tr -d ' -' | sort -u | awk '{ print length, $0 }' | sort -n -r | cut -d" " -f2- | (
		while IFS='' read -r isbn || [[ -n "$isbn" ]]; do
			if is_isbn_valid "$isbn"; then
				echo "$isbn"
			fi
		done
	) | paste -sd "," -
}

organize_by_isbns() {
	# args: isbn, filename
	decho "TODO: organizing ebook $2 by ISBNs '$1'! TODO: get metainfo by isbn"
}

organize_by_filename_and_meta() {
	# args: filename
	decho "TODO: organizing ebook $1 by the filename and metadata! TODO split filename into words, extract metadata stuff if present try to get the opf from the filename, but move it to a 'to check' folder if successful"
}

move_to_organized() {
	# args: book filename, opf filename
	decho TODO get isbns, authors, title, etc from opf file; move book to folder
}

convert_to_txt() {
	#args: input filename, output filename, mimetype
	case "$3" in
		application/pdf ) pdftotext "$1" "$2";;
		*) ebook-convert "$1" "$2";;
	esac
}

search_file_for_isbns() {
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
	decho -e "Ebook metadata:\n\t${ebookmeta/$'\n'/'\n\t'}"
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
	if 7z x -o"$tmpdir" "$1" >&2; then
		decho "Archive extracted successfully in $tmpdir, scanning contents recursively..."
		while IFS= read -r -d '' file_to_check; do
			decho "Searching '$file_to_check' for ISBNs..."
			isbns="$(search_file_for_isbns "$file_to_check")"
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
	if convert_to_txt "$1" "$tmptxtfile" "$mimetype" >&2; then
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
		echo "Organizing '$1' by ISBNs '$isbns'!"
		organize_by_isbns "$isbns" "$1"
	else
		echo "No ISBNs found for '$1', organizing by filename..."
		organize_by_filename_and_meta "$1"
	fi
}


for fpath in "$@"; do
	decho "Recursively scanning '$fpath' for files"
	find "$fpath" -type f  -print0 | sort -z | while IFS= read -r -d '' file_to_check
	do
		decho "Found file '$file_to_check', trying to organize..."
		organize_file "$file_to_check"
	done
done





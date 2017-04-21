#!/usr/bin/env bash

set -euo pipefail

GREEN='\033[0;32m' #shellcheck disable=SC2034
RED='\033[0;31m' #shellcheck disable=SC2034
NC='\033[0m' #shellcheck disable=SC2034

ISBN_REGEX='(?<![0-9])(977|978|979)?(([ -]?[0-9][ -]?){9}[0-9xX])(?![0-9])'
ISBN_DIRECT_GREP_FILES='^text/(plain|xml|html)$'
ISBN_IGNORED_FILES='^image/(png|jpeg|gif)$'

# If the VERBOSE flag is on, outputs the arguments to stderr
decho () {
	if [[ "${VERBOSE:-true}" == true ]]; then
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
	{ grep -oP "$ISBN_REGEX" || true; } | tr -d ' -' | awk '!x[$0]++' | (
		while IFS='' read -r isbn || [[ -n "$isbn" ]]; do
			if is_isbn_valid "$isbn"; then
				echo "$isbn"
			fi
		done
	) | paste -sd "," -
}


is_valid_pdf() {
	echo "TODO"
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
			decho "Extracted ISBNs '$isbns' from the converted text output!"
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



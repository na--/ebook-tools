#!/usr/bin/env bash

set -euo pipefail

VERSION="0.2" #shellcheck disable=SC2034

GREEN='\033[0;32m' #shellcheck disable=SC2034
RED='\033[0;31m' #shellcheck disable=SC2034
BOLD='\033[1m' #shellcheck disable=SC2034
NC='\033[0m' #shellcheck disable=SC2034

VERBOSE=false
DRY_RUN=false
SYMLINK_ONLY=false
DELETE_METADATA=false

TESTED_ARCHIVE_EXTENSIONS='^(7z|bz2|chm|arj|cab|gz|tgz|gzip|zip|rar|xz|tar|epub|docx|odt|ods|cbr|maff)$'

# This regular expression should match most ISBN10/13-like sequences in
# texts. To minimize false-positives, matches should be passed through
# is_isbn_valid() or another ISBN validator
ISBN_REGEX='(?<![0-9])(977|978|979)?+(([ –—-]?[0-9][ –—-]?){9}[0-9xX])(?![0-9-])'
ISBN_DIRECT_GREP_FILES='^text/(plain|xml|html)$'
ISBN_IGNORED_FILES='^image/(png|jpeg|gif)|application/(x-shockwave-flash|CDFV2|vnd.ms-opentype|x-font-ttf|x-dosexec|vnd.ms-excel|x-java-applet)|audio/.+$'
ISBN_RET_SEPARATOR=","

# These options specify if and how we should reoder ISBN_DIRECT_GREP files
# before passing them to find_isbns(). If true, the first
# ISBN_GREP_RF_SCAN_FIRST lines of the files are passed as is, then we pass
# the last ISBN_GREP_RF_REVERSE_LAST in reverse order and finally we pass the
# remainder in the middle. There is no issue if files have fewer lines, there
# will be no duplicate lines passed to grep.
ISBN_GREP_REORDER_FILES=true
ISBN_GREP_RF_SCAN_FIRST=400
ISBN_GREP_RF_REVERSE_LAST=50

# Require Calibre 2.84+, previous versions will search in all enabled sources in the GUI
ISBN_METADATA_FETCH_ORDER="Goodreads,Amazon.com,Google,ISBNDB,WorldCat xISBN,OZON.ru"
ORGANIZE_WITHOUT_ISBN_SOURCES="Goodreads,Amazon.com,Google"

# Should be matched against a lowercase filename.ext, lines that start with #
# and newlines are removed. The default value should filter out most periodicals
WITHOUT_ISBN_IGNORE="$(echo '
# Perdiodicals with filenames that contain something like 2010-11, 199010, 2015_7, 20110203:
(^|[^0-9])(19|20)[0-9][0-9][ _\.-]*(0?[1-9]|10|11|12)([0-9][0-9])?($|[^0-9])
# Periodicals with month numbers before the year
|(^|[^0-9])([0-9][0-9])?(0?[1-9]|10|11|12)[ _\.-]*(19|20)[0-9][0-9]($|[^0-9])
# Periodicals with months or issues
|((^|[^a-z])(jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|aug(ust)?|sep(tember)?|oct(ober)?|nov(ember)?|dec(ember)?|mag(azine)?|issue|#[ _\.-]*[0-9]+)+($|[^a-z]))
# Periodicals with seasons and years
|((spr(ing)?|sum(mer)?|aut(umn)?|win(ter)?|fall)[ _\.-]*(19|20)[0-9][0-9])
|((19|20)[0-9][0-9][ _\.-]*(spr(ing)?|sum(mer)?|aut(umn)?|win(ter)?|fall))
# TODO: include words like monthly, vol(ume)?
' | grep -v '^#' | tr -d '\n')"

TOKEN_MIN_LENGTH=3
TOKENS_TO_IGNORE='ebook|book|novel|series'

#shellcheck disable=SC2016
OUTPUT_FILENAME_TEMPLATE='"${d[AUTHORS]// & /, } - ${d[SERIES]+[${d[SERIES]}] - }${d[TITLE]/:/ -}${d[PUBLISHED]+ (${d[PUBLISHED]%%-*})}${d[ISBN]+ [${d[ISBN]}]}.${d[EXT]}"'
OUTPUT_METADATA_EXTENSION="meta"


# Handle parsing from arguments and setting all the common config vars
#shellcheck disable=SC2034
handle_script_arg() {
	local arg="$1"
	case "$arg" in
		-v|--verbose) VERBOSE=true ;;
		-d|--dry-run) DRY_RUN=true ;;
		-sl|--symlink-only) SYMLINK_ONLY=true ;;
		-dm|--delete-metadata) DELETE_METADATA=true ;;

		--tested-archive-extensions=*) TESTED_ARCHIVE_EXTENSIONS="${arg#*=}" ;;
		-i=*|--isbn-regex=*) ISBN_REGEX="${arg#*=}" ;;
		--isbn-direct-grep-files=*) ISBN_DIRECT_GREP_FILES="${arg#*=}" ;;
		--isbn-extraction-ignore=*) ISBN_IGNORED_FILES="${arg#*=}" ;;
		--reorder-files-for-grep=*)
			i="${arg#*=}"
			if [[ "$arg" == "false" ]]; then
				ISBN_GREP_REORDER_FILES=false
			else
				ISBN_GREP_REORDER_FILES=true
				ISBN_GREP_RF_SCAN_FIRST="${arg%,*}"
				ISBN_GREP_RF_REVERSE_LAST="${arg##*,}"
			fi
		;;

		--token-min-length=*) TOKEN_MIN_LENGTH="${arg#*=}" ;;
		--tokens-to-ignore=*) TOKENS_TO_IGNORE="${arg#*=}" ;;

		-mfo=*|--metadata-fetch-order=*) ISBN_METADATA_FETCH_ORDER="${arg#*=}" ;;
		-owis=*|--organize--without--isbn-sources=*) ORGANIZE_WITHOUT_ISBN_SOURCES="${arg#*=}" ;;
		-wii=*|--without-isbn-ignore=*) WITHOUT_ISBN_IGNORE="${arg#*=}" ;;

		-oft=*|--output-filename-template=*) OUTPUT_FILENAME_TEMPLATE="${arg#*=}" ;;
		-ome=*|--output-metadata-extension=*) OUTPUT_METADATA_EXTENSION="${arg#*=}" ;;

		-*) echo "Invalid option '$arg'"; exit 4; ;;
	esac
}


# If the VERBOSE flag is on, outputs the arguments to stderr
decho () {
	if [[ "${VERBOSE:-false}" == true ]]; then
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
	local prefix="$1"
	if (( $# > 1 )); then
		local should_fit_in="$2"
		if (( should_fit_in > 0 )); then
			if (( ${#prefix} > should_fit_in )); then
				prefix="${prefix:0:10}..${prefix:(-$((should_fit_in - 12)))}"
			else
				prefix="$(printf "%-${should_fit_in}s" "$prefix")"
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


# Converts to lowercase (with unicode support)
to_lower() {
	sed -E 's/[[:upper:]]+/\L&/g'
}

# Prints only the first instance of any line
uniq_no_sort() {
	awk '!x[$0]++'
}


# Validates ISBN-10 and ISBN-13 numbers
is_isbn_valid() {
	local isbn sum=0
	isbn="$(echo "$1" | tr -d ' -' | tr '[:lower:]' '[:upper:]')"

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


# Reads and echoes only n lines from STDIN, without consuming the rest
cat_n() {
	local lines=0
	while ((lines++ < $1 )) && read -r line; do
		echo "$line"
	done
}


# If ISBN_GREP_REORDER_FILES is enabled, reorders the specified file according
# to the values of ISBN_GREP_RF_SCAN_FIRST and ISBN_GREP_RF_REVERSE_LAST
cat_file_for_isbn_grep() {
	if [[ "$ISBN_GREP_REORDER_FILES" == true ]]; then
		decho "Reordering input file (if possible, read first $ISBN_GREP_RF_SCAN_FIRST lines normally, then read last $ISBN_GREP_RF_REVERSE_LAST lines in reverse and then read the rest"

		{ cat_n "$ISBN_GREP_RF_SCAN_FIRST"; tac | { cat_n "$ISBN_GREP_RF_REVERSE_LAST"; tac; } } < "$1"
	else
		cat "$1"
	fi
}


# Searches STDIN for ISBN-like sequences and removes duplicates (preserving
# the order) and finally validates them using is_isbn_valid() and returns
# them separated by $ISBN_RET_SEPARATOR
find_isbns() {
	local isbn
	{ grep -oP "$ISBN_REGEX" || true; } | tr -c -d '0-9xX\n' | uniq_no_sort | (
		while IFS='' read -r isbn || [[ -n "$isbn" ]]; do
			if is_isbn_valid "$isbn"; then
				echo "$isbn"
			fi
		done
	) | paste -sd "$ISBN_RET_SEPARATOR"
}


# Returns non-zero status if the supplied command does not exist
command_exists() {
	command -v "$1" >/dev/null 2>&1
}


# Return "$1/$2" if no file exists at this path. Otherwrise, sequentially
# insert " ($n)" before the extension of $2 and return the first path for
# which no file is present.
unique_filename() {
	local new_path="$1/$2" counter=0
	while [[ -e "$new_path" ]]; do
		counter="$((counter+1))"
		decho "File '$new_path' already exists in destination '$1', trying with counter $counter!"
		new_path="${1}/${2%.*} ($counter).${2##*.}"
	done
	echo "$new_path"
}


# Returns a single value by key by parsing the calibre-style text metadata
# hashmap that is passed to stdin
grep_meta_val() {
	{ grep --max-count=1 "^$1" || true; } | awk -F' : ' '{ print $2 }'
}


# Splits the stdin stream into alpha or numeric tokens with length at least
# $3 (or $TOKEN_MIN_LENGTH), converts them to lowercase, optionally
# deduplicates them (if $2 is true or not specified) and finally concatenates
# them with $1 (or ' ' if not specified)
tokenize() {
	local separator="${1:- }" dedup="${2:-true}"
	local lenr="${3:-$TOKEN_MIN_LENGTH}" tokens_to_ignore="${4:-$TOKENS_TO_IGNORE}"
	{ grep -oE "[[:alpha:]]{${lenr},}|[[:digit:]]{${lenr},}" || true; } | to_lower | {
		if [[ "$dedup" == true ]]; then
			uniq_no_sort
		else
			cat
		fi
	} | {
		if [[ "$tokens_to_ignore" != "" ]]; then
			grep -ivE "^($tokens_to_ignore)\$"
		else
			cat
		fi
	} | paste -sd "$separator"
}


# Checks the supplied file for different kinds of corruption:
#  - If it's zero-sized or contains only \0
#  - If it's has a pdf extension but different mime type
#  - If it's a pdf and pdfinfo returns an error
#  - If it has an archive extension but `7z t` returns an error
check_file_for_corruption() {
	local file_path="$1"
	decho "Testing '$file_path' for corruption..."

	if [[ "$(tr -d '\0' < "$file_path" | head -c 1)" == "" ]]; then
		echo "The file is empty or contains only zeros!"
		return
	fi

	local ext="${1##*.}" mimetype
	mimetype="$(file --brief --mime-type "$file_path")"

	if [[ "$mimetype" == "application/octet-stream" && "$ext" =~ ^(pdf|djv|djvu)$ ]]; then
		echo "The file has a .$ext extension but '$mimetype' MIME type!"
	elif [[ "$mimetype" == "application/pdf" ]]; then
		decho "Checking pdf file for integrity..."
		if ! command_exists pdfinfo; then
			decho "pdfinfo does not exist, could not check if pdf is OK"
		else
			local pdfinfo_output
			if ! pdfinfo_output="$(pdfinfo "$file_path" 2> >(tail | debug_prefixer "[pdfinfo-err|tail] " 0 --width=80 -s))"; then
				decho "pdfinfo returned an error!"
				echo "$pdfinfo_output" | debug_prefixer "[pdfinfo] " 0 --width=80 -t
				echo "Has pdf MIME type or extension, but pdfinfo returned an error!"
				return
			else
				decho "pdfinfo returned successfully"
				echo "$pdfinfo_output" | debug_prefixer "[pdfinfo] " 0 --width=80 -t
				if echo "$pdfinfo_output" | grep --quiet -E "^Page size:\s*0 x 0 pts$"; then
					decho "pdf is corrupt anyway, page size property is empty!"
					echo "pdf can be parsed, but page size is 0 x 0 pts!"
				fi
			fi
		fi
	fi

	if [[ "$ext" =~ $TESTED_ARCHIVE_EXTENSIONS ]]; then
		decho "The file has a '.$ext' extension, testing with 7z..."
		local log

		if ! log="$(7z t "$file_path" 2>&1)"; then
			decho "Test failed!"
			echo "$log" |  debug_prefixer "[7z-test-log] " 0 --width=80 -s
			echo "Looks like an archive, but testing it with 7z failed!"
		fi
	fi
}


# Tries to convert the supplied ebook file into .txt. It uses calibre's
# ebook-convert tool. For optimization, if present, it will use pdftotext
# for pdfs and catdoc for word files.
# Arguments: input path, output path (shloud have .txt extension), mimetype
convert_to_txt() {
	if [[ "$3" == "application/pdf" ]] && command_exists pdftotext; then
		pdftotext "$1" "$2"
	elif [[ "$3" == "application/msword" ]] && command_exists catdoc; then
		catdoc "$1" > "$2"
	else
		ebook-convert "$1" "$2"
	fi
}


# Arguments: the path to the archive file
get_all_isbns_from_archive() {
	local file_path="$1" isbns tmpdir
	tmpdir="$(mktemp -d)"

	decho "Trying to decompress '$file_path' into tmp folder '$tmpdir' and recursively scan the contents"
	if ! 7z x -o"$tmpdir" "$file_path" 2>&1 | debug_prefixer "[7zx] " 0 --width=80 -s; then
		decho "Error extracting the file (probably not an archive)! Removing tmp dir..."
		rm -rf "$tmpdir"
		return 1
	fi

	decho "Archive extracted successfully in '$tmpdir', scanning contents recursively..."
	while IFS= read -r -d '' file_to_check; do
		#decho "Searching '$file_to_check' for ISBNs..."
		isbns="$(search_file_for_isbns "$file_to_check" 2> >(debug_prefixer "[${file_to_check#$tmpdir}] " "${DEBUG_PREFIX_LENGTH:-40}") )"
		if [[ "$isbns" != "" ]]; then
			decho "Found ISBNs $isbns!"
			echo "$isbns" | tr "$ISBN_RET_SEPARATOR" '\n'
		fi
		decho "Removing '$file_to_check'..."
		rm "$file_to_check"
	done < <(find "$tmpdir" -type f  -print0 | sort -z)

	decho "Removing temporary folder '$tmpdir' (should be empty)..."
	find "$tmpdir" -type d -empty -delete
}


# Tries to find ISBN numbers in the given ebook file by using progressively
# more "expensive" tactics. If at some point ISBN numbers are found, they
# are echoed to stdout and the function returns.
# These are the steps:
#   - Check the supplied file name and path for ISBNs
#   - If the MIME type of the file matches ISBN_DIRECT_GREP_FILES, search
#     the file contents directly for ISBNs
#   - If the MIME type matches ISBN_IGNORED_FILES, the function returns early
#   - Check the file metadata from calibre's `ebook-meta` for ISBNs
#   - Try to extract the file as an archive with `7z`; if successful,
#     recursively call search_file_for_isbns for all the extracted files
#   - Try to convert the file to a .txt via convert_to_txt()
search_file_for_isbns() {
	local file_path="$1" isbns
	decho "Searching file '$file_path' for ISBN numbers..."

	isbns="$(echo "$file_path" | find_isbns)"
	if [[ "$isbns" != "" ]]; then
		decho "Extracted ISBNs '$isbns' from file path!"
		echo -n "$isbns"
		return
	fi

	local mimetype
	mimetype="$(file --brief --mime-type "$file_path")"
	decho "Ebook MIME type: $mimetype"
	if [[ "$mimetype" =~ $ISBN_DIRECT_GREP_FILES ]]; then
		decho "Ebook is in text format, trying to find ISBN directly"
		isbns="$(cat_file_for_isbn_grep "$file_path" | find_isbns)"
		if [[ "$isbns" != "" ]]; then
			decho "Extracted ISBNs '$isbns' from the text file contents!"
			echo -n "$isbns"
		else
			decho "Did not find any ISBNs"
		fi
		return
	elif [[ "$mimetype" =~ $ISBN_IGNORED_FILES ]]; then
		decho "The file type in the blacklist, ignoring..."
		return
	fi

	local ebookmeta
	ebookmeta="$(ebook-meta "$file_path")"
	decho "Ebook metadata:"
	echo "$ebookmeta" | debug_prefixer "	" 0 --width=80 -t
	isbns="$(echo "$ebookmeta" | find_isbns)"
	if [[ "$isbns" != "" ]]; then
		decho "Extracted ISBNs '$isbns' from calibre ebook metadata!"
		echo -n "$isbns"
		return
	fi


	if isbns="$(get_all_isbns_from_archive "$file_path" | uniq_no_sort | paste -sd "$ISBN_RET_SEPARATOR")"; then
		if [[ "$isbns" != "" ]]; then
			decho "Extracted ISBNs '$isbns' from the archive file!"
			echo -n "$isbns"
			return
		fi
	else
		local tmptxtfile
		tmptxtfile="$(mktemp --suffix='.txt')"
		decho "Converting ebook to text format in file '$tmptxtfile'..."
		if convert_to_txt "$file_path" "$tmptxtfile" "$mimetype" 2>&1 | debug_prefixer "[ebook2txt] " 0 --width=80 -s; then
			decho "Conversion is done, trying to find ISBNs in the text output..."
			isbns="$(cat_file_for_isbn_grep "$tmptxtfile" | find_isbns)"
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
	fi

	decho "Could not find any ISBNs in '$file_path' :("
}


move_or_link_file() {
	local current_path="$1" new_path="$2" new_folder="${2%/*}"

	$DRY_RUN && decho "(DRY RUN! All operations except metadata deletion are skipped!)"

	if [[ ! -d "$new_folder" ]]; then
		decho "Creating folder '$new_folder'"
		$DRY_RUN || mkdir -p "$new_folder"
	fi

	if [[ "$SYMLINK_ONLY" == true ]]; then
		decho "Symlinking file '$current_path' to '$new_path'..."
		$DRY_RUN || ln -s "$(realpath "$current_path")" "$new_path"
	else
		decho "Moving file '$current_path' to '$new_path'..."
		$DRY_RUN || mv --no-clobber "$current_path" "$new_path"
	fi
}


# Arguments: new_folder, current_ebook_path, current_metadata_path
move_or_link_ebook_file_and_metadata() {
	local new_folder="$1" current_ebook_path="$2" current_metadata_path="$3" line
	declare -A d=( ["EXT"]="${current_ebook_path##*.}" ) # metadata and the file extension

	while IFS='' read -r line || [[ -n "$line" ]]; do
		d["$(echo "${line%%:*}" | sed -e 's/[ \t]*$//' -e 's/ /_/g' -e 's/[^a-zA-Z0-9_]//g' -e 's/\(.*\)/\U\1/')"]="$(echo "${line#*: }" | sed -e 's/[\\/\*\?<>\|\x01-\x1F\x7F\x22\x24\x60]/_/g' | cut -c 1-100 )"
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
	echo -n "$new_path"

	move_or_link_file "$current_ebook_path" "$new_path"

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


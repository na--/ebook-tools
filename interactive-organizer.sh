#!/usr/bin/env bash

set -eEuo pipefail

[ -z "${OUTPUT_FOLDERS:+x}" ] && OUTPUT_FOLDERS=()

: "${QUICK_MODE:=false}"
: "${CUSTOM_MOVE_BASE_DIR:=""}"
: "${RESTORE_ORIGINAL_BASE_DIR:=""}"

# GNU sed extended expressions that aim to mask differences between the old and
# new book filenames due to diacritics and special characters. The default
# value is set below  the script argument parser.
[ -z "${DIACRITIC_DIFFERENCE_MASKINGS:+x}" ] && DIACRITIC_DIFFERENCE_MASKINGS=()

: "${MATCH_PARTIAL_WORDS:=false}"
: "${VERBOSE:=true}"

# shellcheck source=./lib.sh
. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib.sh"

print_help() {
	echo "Interactive eBook organizer v$VERSION"
	echo
	echo "Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS] EBOOK_FOLDERS..."
	echo
	echo "For information about the possible options, see the README.md file or the script source itself"
}

for arg in "$@"; do
	case $arg in
		-qm|--quick-mode) QUICK_MODE=true ;;
		-o=*|--output-folder=*) OUTPUT_FOLDERS+=("${arg#*=}") ;;
		-cmbd=*|--custom-move-base-dir=*) CUSTOM_MOVE_BASE_DIR="${arg#*=}" ;;
		-robd=*|--restore-original-base-dir=*) RESTORE_ORIGINAL_BASE_DIR="${arg#*=}" ;;
		-ddm=*|--diacritic-difference-masking=*) DIACRITIC_DIFFERENCE_MASKINGS+=("${arg#*=}") ;;
		-mpw|--match-partial-words) MATCH_PARTIAL_WORDS=true ;;
		-h|--help) print_help; exit 1 ;;
		-*|--*) handle_script_arg "$arg" ;;
		*) break ;;
	esac
	shift # past argument=value or argument with no value
done
unset -v arg
if [[ "$#" == "0" ]]; then print_help; exit 2; fi

# Set the default sed expressions to mask differences due to diacritical marks
# and special characters. More info:
# https://en.wikipedia.org/wiki/Diacritic
# https://en.wikipedia.org/wiki/English_terms_with_diacritical_marks
# https://stackoverflow.com/questions/20937864/how-to-do-an-accent-insensitive-grep
if (( ${#DIACRITIC_DIFFERENCE_MASKINGS[@]} == 0 )); then
	DIACRITIC_DIFFERENCE_MASKINGS=(
		's/(ae|æ)/(ae|æ)/g'
		's/(ss|ß)/(ss|ß)/g'
		's/([[=a=][=e=][=i=][=o=][=u=][=c=][=n=][=s=][=z=]])/[[=\1=]]/g'
	)
fi


get_old_path() {
	local cf_path="$1" metadata_path="$2" old_path
	if [[ -f "$metadata_path" ]]; then
		old_path="$(grep_meta_val "Old file path" < "$metadata_path")"
	fi
	echo "${old_path:-$cf_path}"
}

get_option() {
	local i choice old_path="$1"

	decho "Possible actions: "
	for i in "${!OUTPUT_FOLDERS[@]}"; do
		if [[ "$i" == "0" ]]; then
			decho -ne " ${BOLD}$i/spb${NC})	"
		else
			decho -ne " ${BOLD}$i${NC})	"
		fi
		decho "Move file and metadata to '${OUTPUT_FOLDERS[$i]}'"
	done

	if [[ "$RESTORE_ORIGINAL_BASE_DIR" != "" ]]; then
		decho -e " ${BOLD}r${NC})	Restore file with original path to '${RESTORE_ORIGINAL_BASE_DIR%/}/${old_path#./}' and delete metadata"
	fi

	decho -e " ${BOLD}m/tab${NC})	Move to another folder		| ${BOLD}i/bs${NC})	 Interactively reorganize the file"
	decho -e " ${BOLD}o/ent${NC})	Open file in external viewer	| ${BOLD}l${NC})	 Read in terminal"
	decho -e " ${BOLD}c${NC})	Read the saved metadata file	| ${BOLD}?${NC})	 Run ebook-meta on the file"
	decho -e " ${BOLD}t/\`${NC})	Run shell in terminal		| ${BOLD}e${NC})	 Eval code (change env vars)"
	decho -e " ${BOLD}s${NC})	Skip file			| ${BOLD}q/esc${NC}) Quit"

	IFS= read -r -s -n1 choice < /dev/tty
	#decho "Character code: $(printf '%02d' "'$choice")" #'
	case "$(printf '%02d' "'$choice")" in #'
		"08"|"127") echo -n "i" ;;	# backspace
		"09") echo -n "m" ;;	# horizontal tab
		"32") echo -n "0" ;;	# space
		"00") echo -n "o" ;;	# null (for newline)
		"96") echo -n "t" ;;	# backtick
		"27") echo -n "q" ;;	# escape
		*) echo -n "$choice" ;;	# everything else'
	esac
}


open_with_less() {
	local file_path="$1" mimetype
	mimetype="$(file --brief --mime-type "$file_path")"
	echo "Reading '$file_path' ($mimetype) with less..."
	if [[ "$mimetype" =~ $ISBN_DIRECT_GREP_FILES ]]; then
		less "$file_path" </dev/tty >/dev/tty
		return
	fi

	local tmptxtfile
	tmptxtfile="$(mktemp --suffix='.txt')"
	echo "Converting ebook '$file_path' to text format in file '$tmptxtfile'..."

	local cresult
	if cresult="$(convert_to_txt "$file_path" "$tmptxtfile" "$mimetype" 2>&1)"; then
		less "$tmptxtfile" </dev/tty >/dev/tty
	else
		echo "Conversion failed!"
		echo "$cresult"
	fi

	decho "Removing tmp file '$tmptxtfile'..."
	rm "$tmptxtfile"
}

move_or_link_file_and_maybe_meta() {
	local new_folder="$1" cf_path="$2" metadata_path="$3" cf_name new_path new_metadata_path
	cf_name="$(basename "$cf_path")"
	new_path="$(unique_filename "${new_folder%/}" "$cf_name")"
	new_metadata_path="$new_path.${OUTPUT_METADATA_EXTENSION}"

	move_or_link_file "$cf_path" "$new_path" 2>&1

	if [[ -f "$metadata_path" ]]; then
		move_or_link_file "$metadata_path" "$new_metadata_path" 2>&1
	fi
}

cgrep() {
	GREP_COLOR="$1" grep --color=always -iE "^|${2:-^}"
}

header_and_check() {
	local cf_path="$1" metadata_path="$2" cf_name cf_hsize
	cf_name="$(basename "$cf_path")"
	cf_hsize="$(numfmt --to=iec-i --suffix=B --format='%.1f' "$(stat -c '%s' "$cf_path")")"

	echo -en "File	'$cf_name' (${BOLD}${cf_hsize}${NC} in '${cf_path%/*}/')"
	if [[ !  -f "$metadata_path" ]]; then
		echo -e " ${BOLD}${RED}[no metadata]${NC}"
		return 1
	fi
	echo -e " ${BOLD}[has metadata]${NC}"

	local cf_tokens masked_cf_tokens sed_expr sed_exprs=()
	for sed_expr in "${DIACRITIC_DIFFERENCE_MASKINGS[@]:-}"; do
		sed_exprs+=("${sed_expr:+--expression=$sed_expr}")
	done
	cf_tokens=$(echo "${cf_name%.*}" | tokenize $'\n')
	masked_cf_tokens=$(echo "$cf_tokens" | stream_concat '|' | sed -E "${sed_exprs[@]:-}")

	local old_path old_name old_name_hl missing_word missing_words=() partial_words=()
	old_path=$(get_old_path "$cf_path" "$metadata_path")
	old_name=$(basename "$old_path")

	while read -r missing_word || [[ -n "$missing_word" ]]; do
		if echo "$cf_tokens" | grep -qiE "^$(echo "$missing_word" | sed -E "${sed_exprs[@]:-}")"; then
			partial_words+=("$missing_word")
		else
			missing_words+=("$missing_word")
		fi
	done < <(echo "${old_name%.*}" | tokenize $'\n' | { grep -ivE "^($masked_cf_tokens)+\$" || true; })

	old_name_hl=$(echo "$old_name" |
		cgrep '1;31' "$(str_concat '|' ${missing_words[@]:+"${missing_words[@]}"})" |
		cgrep '1;33' "$(str_concat '|' ${partial_words[@]:+"${partial_words[@]}"})" |
		cgrep '1;32' "$masked_cf_tokens" |
		cgrep '1;30' "$TOKENS_TO_IGNORE" )

	if [[ "$MATCH_PARTIAL_WORDS" != true ]]; then
		missing_words=(${missing_words[@]:+"${missing_words[@]}"} ${partial_words[@]:+"${partial_words[@]}"})
	fi

	echo "Old	'$old_name_hl' (in '${old_path%/*}/')"

	if (( ${#missing_words[@]} != 0 )); then
		echo -e "Missing words from the old file name: ${BOLD}$(str_concat ',' ${missing_words[@]:+"${missing_words[@]}"})${NC}"
		return 2
	fi

	echo -e "${BOLD}No missing words from the old filename in the new!${NC}"
	if [[ "$QUICK_MODE" != true ]]; then
		return 3
	fi
	echo "Quick mode enabled, skipping to the next file"
}


reorganize_interactively() {
	local cf_path="$1" metadata_path="$1.${OUTPUT_METADATA_EXTENSION}" cf_folder="${1%/*}" old_path="" opt
	old_path=$(get_old_path "$cf_path" "$metadata_path")

	read -r -e -i "$(basename "$old_path")" -p "Enter search terms or 'new filename': " opt  < /dev/tty
	echo "Your choice: $opt"
	if [[ "$opt" == "" ]]; then
		return 1
	elif [[ "$opt" =~ ^\'.+\'$ ]]; then
		opt="${opt:1:-1}"
		echo "Renaming file to '$opt', removing the old metadata if present and saving old file path in the new metadata..."
		move_or_link_file "$cf_path" "$cf_folder/$opt"
		if [[ -f "$metadata_path" ]] && [[ "$DRY_RUN" == "false" ]]; then
			rm "$metadata_path"
		fi
		cf_path="$cf_folder/$opt"
		metadata_path="$cf_path.${OUTPUT_METADATA_EXTENSION}"
		if [[ "$DRY_RUN" == "false" ]]; then
			echo "Old file path       : $old_path" > "$metadata_path"
		fi
		review_file "$cf_path"
		return 0
	fi

	local isbn fetch_arg fetch_sources fetch_source tmpmfile
	tmpmfile="$(mktemp --suffix='.txt')"
	isbn="$(echo "$opt" | find_isbns '\n' | head -n1)"
	if [[ "$isbn" != "" ]]; then
		echo "Fetching metadata from sources $ISBN_METADATA_FETCH_ORDER for ISBN '$isbn' into '$tmpmfile'..."
		fetch_arg="--isbn='$isbn'"
		IFS=, read -ra fetch_sources <<< "$ISBN_METADATA_FETCH_ORDER"
	else
		echo "Fetching metadata from sources $ORGANIZE_WITHOUT_ISBN_SOURCES for title '$opt' into '$tmpmfile'..."
		fetch_arg="--title='$opt'"
		IFS=, read -ra fetch_sources <<< "$ORGANIZE_WITHOUT_ISBN_SOURCES"
	fi

	for fetch_source in "${fetch_sources[@]:-}"; do
		decho "Fetching metadata from ${fetch_source:-all sources}..."
		if fetch_metadata "fetch-meta-${fetch_source:-all}" "${fetch_source:-}" "$fetch_arg" > "$tmpmfile"; then
			sleep 0.1
			decho "Successfully fetched metadata: "
			debug_prefixer "[meta] " 0 --width=100 -t < "$tmpmfile"

			read -r -i "y" -n1  -p "Do you want to use these metadata to rename the file (y/n/Q): " opt  < /dev/tty
			case "$opt" in
				y|Y ) echo "You chose yes, renaming the file..." ;;
				n|N ) echo "You chose no, trying the next metadata source..."; continue ;;
				q|Q ) echo "You chose to quit, returning to the main menu!";  break;;
				* ) echo "Invalid choice '$opt', returning to the main menu!"; break;;
			esac

			if [[ -f "$metadata_path" ]]; then
				echo "Removing old metadata file '$metadata_path'..."
				if [[ "$DRY_RUN" == "false" ]]; then
					rm "$metadata_path"
				fi
			fi

			decho "Addding additional metadata to the end of the metadata file..."
			echo "Old file path       : $old_path" >> "$tmpmfile"
			echo "Metadata source     : ${fetch_source:-all}" >> "$tmpmfile"

			if [[ "$isbn" == "" ]]; then
				isbn="$(find_isbns < "$tmpmfile")"
			fi
			if [[ "$isbn" != "" ]]; then
				echo "ISBN                : $isbn" >> "$tmpmfile"
			fi

			decho "Organizing '$cf_path' (with '$tmpmfile')..."
			cf_path="$(move_or_link_ebook_file_and_metadata "$cf_folder" "$cf_path" "$tmpmfile")"
			decho "New path is '$cf_path'! Reviewing the new file..."
			review_file "$cf_path"
			return 0
		fi
	done

	decho "Removing temp file '$tmpmfile'..."
	rm "$tmpmfile"

	return 1
}

review_file() {
	local cf_path="$1" metadata_path="$1.${OUTPUT_METADATA_EXTENSION}"
	while ! header_and_check "$cf_path" "$metadata_path"; do
		local opt old_path
		old_path=$(get_old_path "$cf_path" "$metadata_path")
		opt=$(get_option "$old_path")
		echo "Chosen option: $opt"
		case "$opt" in
			[0-9])
				if (( opt < ${#OUTPUT_FOLDERS[@]} )); then
					move_or_link_file_and_maybe_meta "${OUTPUT_FOLDERS[$opt]}" "$cf_path" "$metadata_path"
					return
				else
					echo "Invalid output path $opt!"
				fi
			;;
			"m"|"r")
				local new_path_default="" new_path=""
				if [[ "$opt" == "m" ]]; then
					new_path_default="${CUSTOM_MOVE_BASE_DIR%/}/"
				else
					new_path_default="${RESTORE_ORIGINAL_BASE_DIR%/}/${old_path#./}"
				fi
				read -r -e -i "$new_path_default" -p "Delete metadata if exists and move the file to: " new_path  < /dev/tty
				if [[ "$new_path" != "" ]]; then
					if [[ "$DRY_RUN" == "false" ]]; then
						mkdir -p "${new_path%/*}"
						mv --no-clobber "$cf_path" "$new_path"
						if [[ -f "$metadata_path" ]]; then
							rm "$metadata_path"
						fi
					fi
					return
				else
					echo "No path entered, ignoring!"
				fi
			;;
			"i") reorganize_interactively "$cf_path" "$metadata_path" && return ;;
			"o") xdg-open "$1" >/dev/null 2>&1 & ;;
			"l") open_with_less "$cf_path" ;;
			"c")
				if [[ -f "$metadata_path" ]]; then
					debug_prefixer " " 8 --width=80 -t < "$metadata_path"
				else
					echo "There is no metadata file present!"
				fi
			;;
			"?") ebook-meta "$cf_path" | debug_prefixer " " 8 --width=80 -t ;;
			"e")
				local evals=""
				read -r -e -i "TOKENS_TO_IGNORE='$TOKENS_TO_IGNORE'" -p "Evaluate: " evals  < /dev/tty
				if [[ "$evals" != "" ]]; then
					eval "$evals"
				fi
			;;
			"t") echo "Launching '$SHELL'..."; "$SHELL" < /dev/tty;;
			"q") exit 0 ;;
			"s") return ;;
			*) echo "Chosen option '$opt' is invalid, try again" ;;
		esac
		echo
	done

	# Quick mode was enabled and the file looked ok!
	move_or_link_file_and_maybe_meta "${OUTPUT_FOLDERS[0]}" "$cf_path" "$metadata_path"
}


for fpath in "$@"; do
	echo "Recursively scanning '$fpath' for files (except .${OUTPUT_METADATA_EXTENSION})"

	find "$fpath" -type f ! -name "*.${OUTPUT_METADATA_EXTENSION}" -print0 | sort -z ${FILE_SORT_FLAGS[@]:+"${FILE_SORT_FLAGS[@]}"} | while IFS= read -r -d '' file_to_review
	do
		review_file "$file_to_review"
		echo "==============================================================================="
		echo
	done
done

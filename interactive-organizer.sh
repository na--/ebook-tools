#!/usr/bin/env bash

set -euo pipefail

DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=./lib.sh
. "$DIR/lib.sh"

OUTPUT_FOLDERS=()

QUICK_MODE=false
IGNORED_DIFFERENCES=""
CUSTOM_MOVE_BASE_DIR=""

VERBOSE=true


print_help() {
	echo "Interactive eBook organizer v$VERSION"
	echo
	echo "Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS] EBOOK_PATHS..."
	echo
	echo "For information about the possible options, see the beginning of the script itself"
}

for arg in "$@"; do
	case $arg in
		-o=*|--output-folder=*) OUTPUT_FOLDERS+=("${arg#*=}") ;;
		-qm=*|--quick-mode=*) QUICK_MODE="${arg#*=}" ;;
		-id=*|--ignored-differences=*) IGNORED_DIFFERENCES="${arg#*=}" ;;
		-cmbd=*|--custom-move-base-dir=*) CUSTOM_MOVE_BASE_DIR="${arg#*=}" ;;
		-h|--help) print_help; exit 1 ;;
		-*|--*) handle_script_arg "$arg" ;;
		*) break ;;
	esac
	shift # past argument=value or argument with no value
done
unset -v arg
if [[ "$#" == "0" ]]; then print_help; exit 2; fi



reorganize_manually() {
	echo "reorganize_manually '$1'..."
	echo "TODO"
	return 1
	# loop through entering isbn/title&author and retreiving information from online sources
	# until the user chooses to accept it
	# then choose an output and move the file with the new metadata (preserving the old) and filename
	# escape returns the user in the upper menu?
}


get_option() {
	local i choice

	decho "Possible actions: "
	for i in "${!OUTPUT_FOLDERS[@]}"; do

		if [[ "$i" == "0" ]]; then
			decho -ne " ${BOLD}$i/spb${NC})	"
		else
			decho -ne " ${BOLD}$i${NC})	"
		fi
		decho "Move file to '${OUTPUT_FOLDERS[$i]}'"
	done
	decho -e " ${BOLD}m/tab${NC})	Move to another folder		| ${BOLD}r/bs${NC})	Reorganize file manually	| ${BOLD}t/\`${NC})	Run shell in terminal"
	decho -e " ${BOLD}o/ent${NC})	Open file in external viewer	| ${BOLD}l${NC})	Read in terminal		| ${BOLD}c${NC})	Read the saved metadata file	"
	decho -e " ${BOLD}s${NC})	Skip file			| ${BOLD}e${NC})	Eval code (change env vars)	| ${BOLD}q${NC}) 	Quit"

	IFS= read -r -s -n1 choice < /dev/tty
	#decho "Character code: $(printf '%02d' "'$choice")" #'
	case "$(printf '%02d' "'$choice")" in #'
		"08"|"127") echo -n "r" ;;	# backspace
		"09") echo -n "m" ;;	# horizontal tab
		"32") echo -n "0" ;;	# space
		"00") echo -n "o" ;;	# null (for newline)
		"96") echo -n "t" ;;	# backtick
		*) echo -n "$choice" ;;	# everything else'
	esac
}

open_in_external_viewer() {
	decho "Opening file in the external viewer"

	xdg-open "$1" >/dev/null 2>&1 &

	echo "TODO: position window"
}

open_with_less() {
	local file_path="$1" mimetype
	mimetype="$(file --brief --mime-type "$file_path")"
	echo "Reading '$file_path' ($mimetype) with less..."
	if [[ "$mimetype" =~ $ISBN_DIRECT_GREP_FILES ]]; then
		less "$file_path"
		return
	fi

	local tmptxtfile
	tmptxtfile="$(mktemp --suffix='.txt')"
	echo "Converting ebook '$file_path' to text format in file '$tmptxtfile'..."

	local cresult
	if cresult="$(convert_to_txt "$file_path" "$tmptxtfile" "$mimetype" 2>&1)"; then
		less "$tmptxtfile"
	else
		echo "Conversion failed!"
		echo "$cresult" | less
	fi

	decho "Removing tmp file '$tmptxtfile'..."
	rm "$tmptxtfile"
}

move_file_meta() {
	#shellcheck disable=SC2016
	echo -e "Moving:	'$2'${3+\n\t'$3'}\nTo:	'$1'"
	echo TODO
}

cgrep() {
	GREP_COLOR="$1" grep --color=always -iE "^|$2"
}

review_file() {
	local cf_path="$1" metadata_path="$1.${OUTPUT_METADATA_EXTENSION}"
	local cf_name cf_tokens old_path old_name old_name_hl missing_words header=""
	cf_name="$(basename "$cf_path")"
	cf_tokens="$(echo "${cf_name%.*}" | tokenize '|')"

	header="File	'$cf_name' (in '${cf_path%/*}/')"
	if [[ -f "$metadata_path" ]]; then
		header="${header} ${BOLD}[has metadata]${NC}"

		old_path="$(grep_meta_val "Old file path" < "$metadata_path")"
		old_name="$(basename "$old_path")"
		missing_words="$(echo "${old_name%.*}" | tokenize '\n' | { grep -ivE "^($cf_tokens)+\$${IGNORED_DIFFERENCES:+|^$IGNORED_DIFFERENCES\$}" || true; } | paste -sd '|')"

		old_name_hl="$(echo "$old_name" | cgrep '1;31' "$missing_words" | cgrep '1;32' "$cf_tokens" | cgrep '1;30' "$IGNORED_DIFFERENCES" )"
		header="${header}\nOld	'$old_name_hl' (in '${old_path%/*}/')"

		if [[ "$missing_words" == "" ]]; then
			header="${header}\n${BOLD}No missing words from the old filename in the new!${NC}"
			if [[ "$QUICK_MODE" == true ]]; then
				echo "Quick mode enabled, skipping to the next file"
				return
			fi
		else
			header="${header}\nMissing words from the old file name: ${BOLD}$missing_words${NC}"
		fi
	else
		metadata_path=""
	fi

	local opt
	while echo -e "$header"; opt="$(get_option)"; do
		echo "Chosen option: $opt"
		case "$opt" in
			[0-9])
				if (( opt < ${#OUTPUT_FOLDERS[@]} )); then
					move_file_meta "${OUTPUT_FOLDERS[$opt]}" "$cf_path" "$metadata_path"
					break
				else
					echo "Invalid output path $opt!"
				fi
			;;
			"m")
				local new_path=""
				read -r -e -i "$CUSTOM_MOVE_BASE_DIR" -p "Move the file to: " new_path  < /dev/tty
				if [[ "$new_path" != "" ]]; then
					move_file_meta "$new_path" "$cf_path" "$metadata_path"
					break
				else
					echo "No path entered, ignoring!"
				fi
			;;
			"r") reorganize_manually "$cf_path" && break ;;
			"o") open_in_external_viewer "$cf_path" ;;
			"l") open_with_less "$cf_path" ;;
			"c")
				if [[ "$metadata_path" != "" ]]; then
					cat "$metadata_path"
				else
					echo "There is no metadata file present!"
				fi
			;;
			"e")
				local evals=""
				read -r -e -i "IGNORED_DIFFERENCES='$IGNORED_DIFFERENCES'" -p "Evaluate: " evals  < /dev/tty
				if [[ "$evals" != "" ]]; then
					eval "$evals"
				fi
			;;
			"t") echo "Launching '$SHELL'..."; "$SHELL" < /dev/tty;;
			"q") exit 0 ;;
			"s") return ;;
			*) echo "Chosen option '$opt' is invalid, try again" ;;
		esac
	done

}


for fpath in "$@"; do
	echo "Recursively scanning '$fpath' for files (except .${OUTPUT_METADATA_EXTENSION})"

	find "$fpath" -type f ! -name "*.${OUTPUT_METADATA_EXTENSION}" -print0 | sort -z | while IFS= read -r -d '' file_to_review
	do

		review_file "$file_to_review"
		echo "==============================================================================="
		echo
	done
done

#!/usr/bin/env bash

set -euo pipefail

DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=./lib.sh
. "$DIR/lib.sh"

OUTPUT_FOLDERS=()

QUICK_MODE=false
MIN_TOKEN_LENGTH=4
IGNORED_DIFFERENCES=""
CUSTOM_MOVE_BASE_DIR=""

VERBOSE=true

export GREP_COLOR='1;32'

print_help() {
	echo "Interactive eBook organizer v$VERSION"
	echo
	echo "Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS] EBOOK_PATHS..."
	echo
	echo "For information about the possible options, see the beginning of the script itself"
}

for i in "$@"; do
	case $i in
		-o=*|--output-folder=*) OUTPUT_FOLDERS+=("${i#*=}") ;;
		-qm=*|--quick-mode=*) QUICK_MODE="${i#*=}" ;;
		-mtl=*|--min-token-length=*) MIN_TOKEN_LENGTH="${i#*=}" ;;
		-id=*|--ignored-differences=*) IGNORED_DIFFERENCES="${i#*=}" ;;
		-cmbd=*|--custom-move-base-dir=*) CUSTOM_MOVE_BASE_DIR="${i#*=}" ;;
		-h|--help) print_help; exit 1 ;;
		-*|--*) handle_script_arg "$i" ;;
		*) break ;;
	esac
	shift # past argument=value or argument with no value
done
if [[ "$#" == "0" ]]; then print_help; exit 2; fi


tokenize() {
	echo "$1" |  grep -oE "[[:alnum:]]{${MIN_TOKEN_LENGTH},}" | sed -E 's/[[:upper:]]+/\L&/g' | awk '!x[$0]++'
}

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

	local mimetype
	mimetype="$(file --brief --mime-type "$1")"
	echo "Reading '$1' ($mimetype) with less..."
	if [[ "$mimetype" =~ $ISBN_DIRECT_GREP_FILES ]]; then
		less "$1"
		return
	fi

	local tmptxtfile
	tmptxtfile="$(mktemp --suffix='.txt')"
	echo "Converting ebook '$1' to text format in file '$tmptxtfile'..."

	local cresult
	if cresult="$(convert_to_txt "$1" "$tmptxtfile" "$mimetype" 2>&1)"; then
		less "$tmptxtfile"
	else
		echo "Conversion failed!"
		echo "$cresult" | less
	fi

	decho "Removing tmp file '$tmptxtfile'..."
	rm "$tmptxtfile"
}

move_file_meta() {
	echo -e "Moving:	'$2'${3+\n\t'$3'}\nTo:	'$1'"
	echo TODO
}

review_file() {
	local cf_path="$1" metadata_path="$1.${OUTPUT_METADATA_EXTENSION}"
	local cf_name cf_tokens old_path old_name old_name_hl
	cf_name="$(basename "$cf_path")"
	cf_tokens="$(tokenize "${cf_name%.*}" | paste -sd '|')"

	echo -n "File	'$cf_name' (in '${cf_path%/*}/')"
	if [[ -f "$metadata_path" ]]; then
		echo -e " ${BOLD}[has metadata]${NC}"

		old_path="$(cat "$metadata_path" | grep_meta_val "Old file path")"
		old_name="$(basename "$old_path")"
		old_name_hl="$(echo "$old_name" | { grep -i --color=always -E "$cf_tokens" || echo "$old_name"; } )"
		echo -e "Old	'$old_name_hl' (in '${old_path%/*}/')"

		local missing_words
		missing_words="$(tokenize "${old_name%.*}" | { grep -i -v -E "^($cf_tokens)+\$" || true; } | paste -sd ',')"
		if [[ "$missing_words" == "" ]]; then
			echo -e "${BOLD}No missing words from the old filename in the new!${NC}"
			if [[ "$QUICK_MODE" == true ]]; then
				echo "Quick mode enabled, skipping to the next file"
				return
			fi
		else
			echo -e "Missing words from the old file name: ${BOLD}$missing_words${NC}"
		fi
	else
		metadata_path=""
	fi

	local opt
	while opt="$(get_option)"; do
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

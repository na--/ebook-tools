#!/usr/bin/env bash

set -euo pipefail

GREEN='\033[0;32m' #shellcheck disable=SC2034
RED='\033[0;31m' #shellcheck disable=SC2034
NC='\033[0m' #shellcheck disable=SC2034

ISBN_REGEX='(?<![0-9])(977|978|979)?(([ -]?[0-9][ -]?){9}[0-9xX])(?![0-9])'


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
	{ grep -oP "$ISBN_REGEX" || true; } | tr -d ' -' | awk '!x[$0]++' | (
		while IFS='' read -r isbn || [[ -n "$isbn" ]]; do
			if is_isbn_valid "$isbn"; then
				echo "$isbn"
			fi
		done
	) | paste -sd "," -
}



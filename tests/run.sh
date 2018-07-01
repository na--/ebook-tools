#!/usr/bin/env bash

set -eEuo pipefail

DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
EXIT_CODE=0

# shellcheck source=./lib.sh
. "$DIR/../lib.sh"

assert_eq() {
	local expected="$1" got="$2" exit_immediately="${3:-false}"
	echo -n "[line $(caller)] "
	if [[ "$expected" != "$got" ]]; then
		echo "ERROR: expected '$expected' but got '$got'"
		EXIT_CODE=11
		if [[ "$exit_immediately" == "true" ]]; then
			exit "$EXIT_CODE"
		fi
	else
		echo "OK"
	fi
}

expect_err() {
	local expr_to_eval="$1" exit_immediately="${2:-false}"
	echo -n "[line $(caller)] "
	if [[ "$($expr_to_eval >/dev/null 2>&1 && echo success)" != "" ]]; then
		echo "ERROR: expected error for expression '$expr_to_eval'"
		EXIT_CODE=12
		if [[ "$exit_immediately" == "true" ]]; then
			exit "$EXIT_CODE"
		fi
	else
		echo "OK"
	fi
}

# Test to_lower
assert_eq "lower" "$(echo 'lower' | to_lower)"
assert_eq "upper" "$(echo 'UPPER' | to_lower)"
assert_eq "utf-8 кирилица" "$(echo 'UTF-8 КИРИЛИЦА' | to_lower)"

# Test uniq_no_sort
assert_eq '' "$(echo -n | uniq_no_sort)"
assert_eq 'no newline' "$(echo -n 'no newline' | uniq_no_sort)"
assert_eq \
	$'zzz\naaa\nbbb' \
	"$(echo $'zzz\nzzz\naaa\nzzz\naaa\nbbb\nbbb' | uniq_no_sort)"

# Test str_concat
expect_err 'str_concat' # The function needs at least 1 argument
assert_eq "testmest123" "$(str_concat "" test mest 123)"
assert_eq $'aa\nbb' "$(str_concat $'\n' aa bb)"

# Test find_isbns
assert_eq "" "$(echo -n | find_isbns)"
assert_eq "" "$(echo "invalid isbn 1122334455" | find_isbns)"
assert_eq "076532637X" "$(echo "just an isbn 076532637X in some text" | find_isbns)"
assert_eq "075640407X,9780756404079" "$(echo "075640407X (ISBN13: 9780756404079)" | find_isbns)"
assert_eq "9781610391849,1610391845" "$(echo "crazy!978-16–103⁻918 49 16 10—39¯1845-z" | find_isbns)"

wrong_but_valid="0123456789,0000000000,1111111111,2222222222,3333333333,4444444444,5555555555,6666666666,7777777777,8888888888,9999999999"

assert_eq "" "$(echo "$wrong_but_valid" | find_isbns)"
assert_eq "$wrong_but_valid" "$(echo "$wrong_but_valid" | ISBN_BLACKLIST_REGEX="" find_isbns)"

exit "$EXIT_CODE"
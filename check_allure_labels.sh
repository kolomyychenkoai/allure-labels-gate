#!/usr/bin/env bash
# Fail the CI build if a test in the Allure results has no required labels.
#
# A label counts only if its value is not empty. Tests whose name contains
# "allure" (in any case) are not checked.
#
# Exit codes:
#   0  every checked test has all required labels
#   1  some tests are missing required labels (they are listed)
#   2  the check could not run: wrong settings, no results, unreadable file, no jq
#
# Requires bash 3.2+ and jq 1.6+. Same behaviour as check_allure_labels.py.

set -euo pipefail

# Settings. An environment variable with the same name, if not empty, wins over
# the value written here. To set the value in the script itself, edit the text after ":-".

# Allure results directory of the project, for example "target/allure-results".
# Required: every project writes its results to its own place.
ALLURE_RESULTS_DIR="${ALLURE_RESULTS_DIR:-}"

# Comma-separated label names every test must have. Names are case-sensitive.
REQUIRED_LABELS="${REQUIRED_LABELS:-epic,feature,owner}"

# Tests whose name contains this text, in any case, are not checked.
EXCLUDE_IF_NAME_CONTAINS="allure"

HINT="Check ALLURE_RESULTS_DIR and that the tests ran before this step."

# Whitespace is limited to these characters so that both scripts agree.
JQ_HELPERS='
def text: if type == "string" then . else "" end;
def blank: text | gsub("[ \t\r\n]"; "") == "";
'

# One line per result file: the file, the test (fullName, name) and the required labels it lacks.
JQ_READ_RESULT="$JQ_HELPERS"'
if type != "object" then error("not a test result") else . end
| [ .labels | if type == "array" then .[] else empty end
    | objects | select((.name | type == "string") and (.value | blank | not)) | .name ]
  as $present
| { file: input_filename,
    test: [ (.fullName | text), (.name | text) ],
    missing: ($required - $present) }
'

# One test is a (fullName, name) pair: invocations of a parameterized test share
# fullName but differ in name. A retried test writes a file per attempt, and a
# label counts if any attempt has it: a failed attempt may stop before the code
# that adds the label.
JQ_SUMMARIZE='
def missing_in_every_attempt:
  map(.missing) as $attempts
  | $required | map(select(. as $label_name | all($attempts[]; any(.[]; . == $label_name))));

group_by(.test)
| map({ fullName: .[0].test[0], name: .[0].test[1], missing: missing_in_every_attempt })
| map(.excluded = (.name | ascii_downcase | contains($exclude)))
| { found: length,
    excluded: map(select(.excluded)) | length,
    failing: map(select((.excluded | not) and (.missing | length > 0))) }
'

JQ_PRINT_FAILING='
def dash_if_empty: if . == "" then "-" else . end;
.failing[]
| "  \(.fullName | dash_if_empty)\n    name:    \(.name | dash_if_empty)\n    missing: \(.missing | join(", "))\n"
'

fail() {
    echo "ERROR: $1" >&2
    exit 2
}

# An unexpected failure must not look like exit code 1, "tests are missing labels".
trap 'fail "unexpected error at line $LINENO of $0. This is a bug in the script; report it with this output."' ERR

list_result_files() {
    local dir="$ALLURE_RESULTS_DIR"
    case "$dir" in
        -*) dir="./$dir" ;;  # otherwise find takes the path for an option
    esac
    find -L "$dir" -maxdepth 1 -type f -name '*-result.json' -print0
}

fail_on_first_unreadable_file() {
    local file
    while IFS= read -r -d '' file; do
        if ! jq -s -e 'length == 1 and (.[0] | type == "object")' "$file" >/dev/null 2>&1; then
            fail "$(basename "$file") in $ALLURE_RESULTS_DIR cannot be read as an Allure test result (expected one JSON object). The file may be cut short if the test run was killed: clean the directory and run the tests again."
        fi
    done < <(list_result_files | LC_ALL=C sort -z)
    fail "could not read the test results in $ALLURE_RESULTS_DIR. Run check_allure_labels.py to see which file fails."
}

command -v jq >/dev/null 2>&1 \
    || fail "jq is not installed. Install jq 1.6+ or use check_allure_labels.py."

required="$(jq -n -c --arg setting "$REQUIRED_LABELS" \
    '$setting | split(",") | map(gsub("^[ \t\r\n]+|[ \t\r\n]+$"; "")) | map(select(length > 0))')"
if [ "$required" = "[]" ]; then
    fail "REQUIRED_LABELS has no label names. Set comma-separated names, for example REQUIRED_LABELS=epic,feature,owner."
fi

if [ -z "$ALLURE_RESULTS_DIR" ]; then
    fail "ALLURE_RESULTS_DIR is not set. Set it to the Allure results directory of this project, for example ALLURE_RESULTS_DIR=target/allure-results."
fi
if [ ! -e "$ALLURE_RESULTS_DIR" ]; then
    fail "Allure results directory does not exist: $ALLURE_RESULTS_DIR. $HINT"
fi
if [ ! -d "$ALLURE_RESULTS_DIR" ]; then
    fail "ALLURE_RESULTS_DIR is not a directory: $ALLURE_RESULTS_DIR. $HINT"
fi

file_count=$(list_result_files | tr -cd '\0' | wc -c)
if [ "$file_count" -eq 0 ]; then
    fail "no test results (*-result.json) in $ALLURE_RESULTS_DIR. $HINT"
fi

records="$(list_result_files \
    | xargs -0 jq -c --argjson required "$required" "$JQ_READ_RESULT" 2>/dev/null)" \
    || fail_on_first_unreadable_file

# jq reads an empty file or two objects in one file without an error,
# so every file must give exactly one record.
one_record_per_file="$(jq -s --argjson file_count "$file_count" \
    'group_by(.file) | length == $file_count and all(.[]; length == 1)' <<<"$records")"
if [ "$one_record_per_file" != "true" ]; then
    fail_on_first_unreadable_file
fi

summary="$(jq -s -c --argjson required "$required" --arg exclude "$EXCLUDE_IF_NAME_CONTAINS" \
    "$JQ_SUMMARIZE" <<<"$records")"
found="$(jq -r '.found' <<<"$summary")"
excluded="$(jq -r '.excluded' <<<"$summary")"
failing="$(jq -r '.failing | length' <<<"$summary")"
checked=$((found - excluded))

echo "Allure results: $ALLURE_RESULTS_DIR"
echo "Required labels: $(jq -r 'join(", ")' <<<"$required")"
echo "Tests found: $found, not checked because the name contains \"$EXCLUDE_IF_NAME_CONTAINS\": $excluded"
echo

if [ "$failing" -eq 0 ]; then
    echo "OK: all $checked checked tests have the required labels."
    exit 0
fi

echo "Tests missing required labels:"
echo
jq -r "$JQ_PRINT_FAILING" <<<"$summary"
echo "FAILED: $failing of $checked checked tests are missing required labels."
exit 1

#!/usr/bin/env bash
# Fail the CI build if a test in the Allure results has no required labels.
#
# A label counts only if its value is not empty. Tests whose name contains
# "allure" (in any case) are not checked.
#
# Settings: edit the values below or set environment variables with the same names.
#
# Exit codes:
#   0  every checked test has all required labels
#   1  some tests are missing required labels (they are listed)
#   2  the check could not run: wrong settings, no results, unreadable file, no jq
#
# Requires bash 3.2+ and jq 1.6+. Same behaviour as check_allure_labels.py.

set -euo pipefail

# Allure results directory of the project, e.g. target/allure-results. Required.
ALLURE_RESULTS_DIR="${ALLURE_RESULTS_DIR:-}"

# Comma-separated names of the labels every test must have.
REQUIRED_LABELS="${REQUIRED_LABELS:-epic,feature,owner}"

EXCLUDE_IF_NAME_CONTAINS="allure"

HINT="Check ALLURE_RESULTS_DIR and that the tests ran before this step."

# Whitespace is limited to these characters so that both scripts agree.
JQ_HELPERS='
def text: if type == "string" then . else "" end;
def blank: text | gsub("[ \t\r\n]"; "") == "";
'

# One line per result file: the test (fullName, name) and the required labels it lacks.
JQ_READ_RESULT="$JQ_HELPERS"'
if type != "object" then error("not a test result") else . end
| [ .labels | if type == "array" then .[] else empty end
    | objects | select(.value | blank | not) | .name ] as $present
| { test: [ (.fullName | text), (.name | text) ],
    missing: ($required - $present) }
'

# A retried test writes one file per attempt with the same name and fullName;
# invocations of a parameterized test share fullName but differ in name.
JQ_SUMMARIZE='
group_by(.test)
| map({ fullName: .[0].test[0],
        name: .[0].test[1],
        missing: ([ .[].missing[] ] as $missing
                  | $required | map(select(. as $name | any($missing[]; . == $name)))) })
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
trap 'fail "unexpected error at line $LINENO of $0."' ERR

list_result_files() {
    find "$ALLURE_RESULTS_DIR" -maxdepth 1 -type f -name '*-result.json' -print0
}

fail_on_first_unreadable_file() {
    local file
    while IFS= read -r -d '' file; do
        if ! jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
            fail "$(basename "$file") in $ALLURE_RESULTS_DIR cannot be read as an Allure test result (expected a JSON object)."
        fi
    done < <(list_result_files | LC_ALL=C sort -z)
    fail "could not read the test results in $ALLURE_RESULTS_DIR."
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
if [ ! -d "$ALLURE_RESULTS_DIR" ]; then
    fail "Allure results directory does not exist: $ALLURE_RESULTS_DIR. $HINT"
fi
if [ -z "$(list_result_files | head -c 1)" ]; then
    fail "no test results (*-result.json) in $ALLURE_RESULTS_DIR. $HINT"
fi

records="$(list_result_files \
    | xargs -0 jq -c --argjson required "$required" "$JQ_READ_RESULT" 2>/dev/null)" \
    || fail_on_first_unreadable_file

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

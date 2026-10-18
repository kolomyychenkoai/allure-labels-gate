#!/usr/bin/env bash
# Runs both scripts on every case in tests/cases and compares output and exit code
# with the case's expected.txt.
#
# Case layout:
#   results/      Allure results the script reads (ALLURE_RESULTS_DIR=results)
#   env           optional KEY=VALUE lines that override the defaults below
#   expected.txt  what the script prints, stdout then stderr, and a last line "exit: N"
#
# PYTHON_BIN and BASH_BIN choose the interpreters, e.g. BASH_BIN=/bin/bash tests/run.sh.
# SCRIPT_DIR points at another copy of the scripts, e.g. a deliberately broken one.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="${SCRIPT_DIR:-$(dirname "$TESTS_DIR")}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
BASH_BIN="${BASH_BIN:-bash}"

run_case() {
    local case_dir="$1" runner="$2" script="$3"
    (
        cd "$case_dir" || exit 2
        export ALLURE_RESULTS_DIR=results
        export REQUIRED_LABELS=epic,feature,owner
        if [ -f env ]; then
            while IFS='=' read -r key value; do
                export "$key=$value"
            done < env
        fi
        "$runner" "$script" 2>&1
        echo "exit: $?"
    )
}

failed=0
total=0
for case_dir in "$TESTS_DIR"/cases/*/; do
    case_name="$(basename "$case_dir")"
    for variant in "python:$PYTHON_BIN:$SCRIPT_DIR/check_allure_labels.py" \
                   "bash:$BASH_BIN:$SCRIPT_DIR/check_allure_labels.sh"; do
        label="${variant%%:*}"
        rest="${variant#*:}"
        runner="${rest%%:*}"
        script="${rest#*:}"
        total=$((total + 1))
        actual="$(run_case "$case_dir" "$runner" "$script")"
        if [ "$actual" == "$(cat "$case_dir/expected.txt")" ]; then
            echo "ok    $label  $case_name"
        else
            failed=$((failed + 1))
            echo "FAIL  $label  $case_name"
            diff <(cat "$case_dir/expected.txt") <(echo "$actual") | sed 's/^/      /'
        fi
    done
done

echo
echo "$((total - failed)) of $total passed"
[ "$failed" -eq 0 ]

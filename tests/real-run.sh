#!/usr/bin/env bash
# Runs real tests with Allure from scratch and checks both scripts on the fresh results:
#   - the whole test suite of a Java service on Maven, with LabelsContractTest added
#     (tests/real/sources),
#   - the official Allure Jest example with labels.spec.js added.
# For each project both scripts must print the same report, and the tests they list
# must be exactly the tests a plain jq query finds without the required labels.
#
# JAVA_SERVICE   Maven project with allure-junit5 (default: ~/projects/testapps/billing)
# MAVEN_ARGS     extra Maven arguments that turn Allure on (default: -Pallure-lib)
#
# Needs Maven and the Java version the service builds with (testapps/billing: Java 25),
# Node.js with npm, git and jq.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCES="$REPO_DIR/tests/real/sources"
JAVA_SERVICE="${JAVA_SERVICE:-$HOME/projects/testapps/billing}"
MAVEN_ARGS="${MAVEN_ARGS:--Pallure-lib}"
REQUIRED_LABELS=epic,feature,owner
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

run_java_service() {
    echo "== Java: $JAVA_SERVICE"
    cp -R "$JAVA_SERVICE" "$WORK/java"
    rm -rf "$WORK/java/target"
    local package_dir="$WORK/java/src/test/java/com/example/billing"
    mkdir -p "$package_dir"
    cp "$SOURCES/LabelsContractTest.java" "$package_dir/"
    # Not -q: the log must show the test run and the retried flaky test.
    (cd "$WORK/java" && mvn $MAVEN_ARGS test \
        -Dsurefire.rerunFailingTestsCount=1 -Dmaven.test.failure.ignore=true \
        -Dallure.results.directory="$WORK/java/target/allure-results" > "$WORK/java.log" 2>&1) \
        || { tail -40 "$WORK/java.log"; return 1; }
    grep -E 'Tests run:.*Flakes|Tests run: [0-9]+, Failures' "$WORK/java.log" | tail -1
    check_results "$WORK/java/target/allure-results"
}

run_js_example() {
    echo "== JavaScript: allure-examples/jest-npm-cjs-js"
    git clone -q --depth 1 https://github.com/allure-examples/jest-npm-cjs-js.git "$WORK/js"
    cp "$SOURCES/labels.spec.js" "$WORK/js/__tests__/"
    (cd "$WORK/js" && npm ci --silent --ignore-scripts > "$WORK/js.log" 2>&1 \
        && { npx jest >> "$WORK/js.log" 2>&1 || true; }) || { tail -40 "$WORK/js.log"; return 1; }
    grep -E '^Tests:' "$WORK/js.log"
    check_results "$WORK/js/allure-results"
}

# Tests without a required label as "fullName | name", found by a plain jq query:
# attempts of one test are grouped, tests where every attempt was skipped are left out.
expected_failing() {
    jq -r -s --arg required "$REQUIRED_LABELS" '
        ($required | split(",")) as $names
        | group_by([.fullName, .name])[]
        | select(any(.[]; .status != "skipped"))
        | select((.[0].name // "" | ascii_downcase | contains("allure")) | not)
        | select([ .[].labels[]? | select((.value // "" | gsub("[ \t\r\n]"; "")) != "") | .name ] as $present
                 | any($names[]; . as $n | $present | index($n) | not))
        | "\(.[0].fullName) | \(.[0].name)"' "$1"/*-result.json | sort -u
}

# Tests the script listed, as "fullName | name".
listed_failing() {
    awk '/^  [^ ]/ { full = substr($0, 3) } /^    name:    / { print full " | " substr($0, 14) }' | sort -u
}

check_results() {
    local results="$1"
    local python_out bash_out
    python_out="$(ALLURE_RESULTS_DIR="$results" REQUIRED_LABELS="$REQUIRED_LABELS" \
        python3 "$REPO_DIR/check_allure_labels.py" 2>&1; echo "exit: $?")"
    bash_out="$(ALLURE_RESULTS_DIR="$results" REQUIRED_LABELS="$REQUIRED_LABELS" \
        bash "$REPO_DIR/check_allure_labels.sh" 2>&1; echo "exit: $?")"
    echo "$python_out" | sed "s|$results|<results>|"

    if [ "$python_out" != "$bash_out" ]; then
        echo "FAIL: the two scripts printed different reports or exit codes"
        diff <(echo "$python_out") <(echo "$bash_out") || true
        return 1
    fi
    if ! diff <(expected_failing "$results") <(echo "$python_out" | listed_failing); then
        echo "FAIL: listed tests differ from the jq query (left: jq, right: script)"
        return 1
    fi
    echo "ok: both scripts agree, and the listed tests match the jq query"
    echo
}

run_java_service
run_js_example

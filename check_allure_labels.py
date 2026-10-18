#!/usr/bin/env python3
"""Fail the CI build if a test in the Allure results has no required labels.

A label counts only if its value is not empty. Tests whose name contains
"allure" (in any case) and skipped tests (@Disabled, it.skip) are not checked.

Exit codes:
  0  every checked test has all required labels
  1  some tests are missing required labels (they are listed)
  2  the check could not run: wrong settings, no results, unreadable file
Any non-zero code fails the build; 2 is kept apart from 1 so that the log
shows a setup problem rather than missing labels.

Requires Python 3.8+, no extra packages. Same behaviour as check_allure_labels.sh.
"""

import json
import os
import sys

# Settings. An environment variable with the same name, if not empty, wins over
# the value written here. To set the value in the script itself, edit the text after "or".

# Allure results directory of the project, for example "target/allure-results".
# Required: every project writes its results to its own place.
ALLURE_RESULTS_DIR = os.environ.get("ALLURE_RESULTS_DIR") or ""

# Comma-separated label names every test must have. Names are case-sensitive.
REQUIRED_LABELS = os.environ.get("REQUIRED_LABELS") or "testStage,System,layer"

# Not read from the environment; edit here if needed.
# Tests whose name contains this text, in any case, are not checked.
EXCLUDE_IF_NAME_CONTAINS = "allure"

# Whitespace is limited to these characters so that both scripts agree.
WHITESPACE = " \t\r\n"

HINT = "Check ALLURE_RESULTS_DIR and that the tests ran before this step."


def fail(message):
    print("ERROR: " + message, file=sys.stderr)
    sys.exit(2)


def parse_required_labels(setting):
    names = [name.strip(WHITESPACE) for name in setting.split(",")]
    names = [name for name in names if name]
    if not names:
        fail("REQUIRED_LABELS has no label names. Set comma-separated names, "
             "for example REQUIRED_LABELS=testStage,System,layer.")
    return names


def find_result_files(results_dir):
    if not results_dir:
        fail("ALLURE_RESULTS_DIR is not set. Set it to the Allure results directory "
             "of this project, for example ALLURE_RESULTS_DIR=target/allure-results.")
    if not os.path.exists(results_dir):
        fail(f"Allure results directory does not exist: {results_dir}. {HINT}")
    if not os.path.isdir(results_dir):
        fail(f"ALLURE_RESULTS_DIR is not a directory: {results_dir}. "
             "Set it to the Allure results directory, not a file.")
    files = sorted(name for name in os.listdir(results_dir)
                   if name.endswith("-result.json")
                   and os.path.isfile(os.path.join(results_dir, name)))
    if not files:
        fail(f"no test results (*-result.json) in {results_dir}. {HINT}")
    return files


def read_result(results_dir, file_name):
    try:
        with open(os.path.join(results_dir, file_name), encoding="utf-8-sig") as file:
            result = json.load(file)
    except (OSError, ValueError):
        result = None
    if not isinstance(result, dict):
        fail(f"{file_name} in {results_dir} cannot be read as an Allure test result "
             "(expected one JSON object). The file may be cut short if the test run was "
             "killed: clean the directory and run the tests again.")
    return result


def text_field(result, key):
    value = result.get(key)
    return value if isinstance(value, str) else ""


def labels_with_value(result):
    labels = result.get("labels")
    if not isinstance(labels, list):
        return set()
    return {label["name"] for label in labels
            if isinstance(label, dict)
            and isinstance(label.get("name"), str)
            and isinstance(label.get("value"), str)
            and label["value"].strip(WHITESPACE)}


def main():
    # Test names are often not in English, and the locale on a CI agent is often not
    # UTF-8: without this, printing such a name crashes the script.
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

    required = parse_required_labels(REQUIRED_LABELS)
    files = find_result_files(ALLURE_RESULTS_DIR)

    # One test is a (fullName, name) pair: invocations of a parameterized test share
    # fullName but differ in name. A retried test writes a file per attempt, and a
    # label counts if any attempt has it: a failed attempt may stop before the code
    # that adds the label. A test is skipped only if every attempt was skipped:
    # a skipped JS test never runs the code that adds labels.
    missing_by_test = {}
    ran = set()
    for file_name in files:
        result = read_result(ALLURE_RESULTS_DIR, file_name)
        test = (text_field(result, "fullName"), text_field(result, "name"))
        present = labels_with_value(result)
        missing = {label for label in required if label not in present}
        if test in missing_by_test:
            missing_by_test[test] &= missing
        else:
            missing_by_test[test] = missing
        if result.get("status") != "skipped":
            ran.add(test)

    with_allure = {(full_name, name) for full_name, name in missing_by_test
                   if EXCLUDE_IF_NAME_CONTAINS in name.lower()}
    skipped = missing_by_test.keys() - ran - with_allure
    checked = missing_by_test.keys() - with_allure - skipped
    failing = sorted(test for test in checked if missing_by_test[test])

    report = [
        "Allure results: " + ALLURE_RESULTS_DIR,
        "Required labels: " + ", ".join(required),
        f'Tests found: {len(missing_by_test)}, not checked: {len(with_allure)} '
        f'with "{EXCLUDE_IF_NAME_CONTAINS}" in the name, {len(skipped)} skipped',
        "",
    ]
    if failing:
        report += ["Tests missing required labels:", ""]
        for full_name, name in failing:
            missing = missing_by_test[(full_name, name)]
            report += [
                "  " + (full_name or "-"),
                "    name:    " + (name or "-"),
                "    missing: " + ", ".join(label for label in required if label in missing),
                "",
            ]
        report.append(f"FAILED: {len(failing)} of {len(checked)} checked tests "
                      "are missing required labels.")
    else:
        report.append(f"OK: all {len(checked)} checked tests have the required labels.")

    print("\n".join(report))
    return 1 if failing else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        # An unexpected failure must not look like exit code 1, "tests are missing labels".
        fail(f"unexpected error: {error!r}. "
             "This is a bug in the script; report it with this output.")

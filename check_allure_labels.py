#!/usr/bin/env python3
"""Fail the CI build if a test in the Allure results has no required labels.

A label counts only if its value is not empty. Tests whose name contains
"allure" (in any case) are not checked.

Exit codes:
  0  every checked test has all required labels
  1  some tests are missing required labels (they are listed)
  2  the check could not run: wrong settings, no results, unreadable file

Requires Python 3.8+, no extra packages. Same behaviour as check_allure_labels.sh.
"""

import json
import os
import sys

# Settings. An environment variable with the same name, if not empty, wins over
# the value written here. To fix a value in the script, change the text after "or".

# Allure results directory of the project, for example "target/allure-results".
# Required: every project writes its results to its own place.
ALLURE_RESULTS_DIR = os.environ.get("ALLURE_RESULTS_DIR") or ""

# Comma-separated label names every test must have. Names are case-sensitive.
REQUIRED_LABELS = os.environ.get("REQUIRED_LABELS") or "epic,feature,owner"

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
             "for example REQUIRED_LABELS=epic,feature,owner.")
    return names


def find_result_files(results_dir):
    if not results_dir:
        fail("ALLURE_RESULTS_DIR is not set. Set it to the Allure results directory "
             "of this project, for example ALLURE_RESULTS_DIR=target/allure-results.")
    if not os.path.exists(results_dir):
        fail("Allure results directory does not exist: {}. {}".format(results_dir, HINT))
    if not os.path.isdir(results_dir):
        fail("ALLURE_RESULTS_DIR is not a directory: {}. {}".format(results_dir, HINT))
    files = sorted(name for name in os.listdir(results_dir)
                   if name.endswith("-result.json")
                   and os.path.isfile(os.path.join(results_dir, name)))
    if not files:
        fail("no test results (*-result.json) in {}. {}".format(results_dir, HINT))
    return files


def read_result(results_dir, file_name):
    try:
        with open(os.path.join(results_dir, file_name), encoding="utf-8-sig") as file:
            result = json.load(file)
    except (OSError, ValueError):
        result = None
    if not isinstance(result, dict):
        fail("{} in {} cannot be read as an Allure test result (expected one JSON object). "
             "The file may be cut short if the test run was killed: clean the directory "
             "and run the tests again.".format(file_name, results_dir))
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
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

    required = parse_required_labels(REQUIRED_LABELS)
    files = find_result_files(ALLURE_RESULTS_DIR)

    # One test is a (fullName, name) pair: invocations of a parameterized test share
    # fullName but differ in name. A retried test writes a file per attempt, and a
    # label counts if any attempt has it: a failed attempt may stop before the code
    # that adds the label.
    missing_by_test = {}
    for file_name in files:
        result = read_result(ALLURE_RESULTS_DIR, file_name)
        test = (text_field(result, "fullName"), text_field(result, "name"))
        present = labels_with_value(result)
        missing = {label for label in required if label not in present}
        if test in missing_by_test:
            missing_by_test[test] &= missing
        else:
            missing_by_test[test] = missing

    excluded = {test for test in missing_by_test
                if EXCLUDE_IF_NAME_CONTAINS in test[1].lower()}
    checked = len(missing_by_test) - len(excluded)
    failing = sorted(test for test, missing in missing_by_test.items()
                     if missing and test not in excluded)

    report = [
        "Allure results: " + ALLURE_RESULTS_DIR,
        "Required labels: " + ", ".join(required),
        'Tests found: {}, not checked because the name contains "{}": {}'
        .format(len(missing_by_test), EXCLUDE_IF_NAME_CONTAINS, len(excluded)),
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
        report.append("FAILED: {} of {} checked tests are missing required labels."
                      .format(len(failing), checked))
    else:
        report.append("OK: all {} checked tests have the required labels.".format(checked))

    print("\n".join(report))
    return 1 if failing else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        # An unexpected failure must not look like exit code 1, "tests are missing labels".
        fail("unexpected error: {!r}. This is a bug in the script; report it with this output."
             .format(error))

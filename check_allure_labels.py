#!/usr/bin/env python3
"""Fail the CI build if a test in the Allure results has no required labels.

A label counts only if its value is not empty. Tests whose name contains
"allure" (in any case) are not checked.

Settings: edit the values below or set environment variables with the same names.

Exit codes:
  0  every checked test has all required labels
  1  some tests are missing required labels (they are listed)
  2  the check could not run: wrong settings, no results, unreadable file

Requires Python 3.8+, no extra packages. Same behaviour as check_allure_labels.sh.
"""

import json
import os
import sys

# Allure results directory of the project, e.g. target/allure-results. Required.
ALLURE_RESULTS_DIR = os.environ.get("ALLURE_RESULTS_DIR") or ""

# Comma-separated names of the labels every test must have.
REQUIRED_LABELS = os.environ.get("REQUIRED_LABELS") or "epic,feature,owner"

EXCLUDE_IF_NAME_CONTAINS = "allure"

# Whitespace is limited to these characters so that both scripts agree.
WHITESPACE = " \t\r\n"


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
    hint = "Check ALLURE_RESULTS_DIR and that the tests ran before this step."
    if not results_dir:
        fail("ALLURE_RESULTS_DIR is not set. Set it to the Allure results directory "
             "of this project, for example ALLURE_RESULTS_DIR=target/allure-results.")
    if not os.path.isdir(results_dir):
        fail("Allure results directory does not exist: {}. {}".format(results_dir, hint))
    files = sorted(name for name in os.listdir(results_dir)
                   if name.endswith("-result.json")
                   and os.path.isfile(os.path.join(results_dir, name)))
    if not files:
        fail("no test results (*-result.json) in {}. {}".format(results_dir, hint))
    return files


def read_result(results_dir, file_name):
    try:
        with open(os.path.join(results_dir, file_name), encoding="utf-8-sig") as file:
            result = json.load(file)
    except (OSError, ValueError):
        result = None
    if not isinstance(result, dict):
        fail("{} in {} cannot be read as an Allure test result (expected a JSON object)."
             .format(file_name, results_dir))
    return result


def text_field(result, key):
    value = result.get(key)
    return value if isinstance(value, str) else ""


def labels_with_value(result):
    labels = result.get("labels")
    if not isinstance(labels, list):
        return set()
    return {label.get("name") for label in labels
            if isinstance(label, dict)
            and isinstance(label.get("value"), str)
            and label["value"].strip(WHITESPACE)}


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

    required = parse_required_labels(REQUIRED_LABELS)
    files = find_result_files(ALLURE_RESULTS_DIR)

    # A retried test writes one file per attempt with the same name and fullName;
    # invocations of a parameterized test share fullName but differ in name.
    missing_by_test = {}
    for file_name in files:
        result = read_result(ALLURE_RESULTS_DIR, file_name)
        test = (text_field(result, "fullName"), text_field(result, "name"))
        present = labels_with_value(result)
        missing = missing_by_test.setdefault(test, set())
        missing.update(label for label in required if label not in present)

    excluded = {test for test in missing_by_test
                if EXCLUDE_IF_NAME_CONTAINS in test[1].lower()}
    checked = len(missing_by_test) - len(excluded)
    failing = sorted(test for test, missing in missing_by_test.items()
                     if missing and test not in excluded)

    print("Allure results: " + ALLURE_RESULTS_DIR)
    print("Required labels: " + ", ".join(required))
    print('Tests found: {}, not checked because the name contains "{}": {}'
          .format(len(missing_by_test), EXCLUDE_IF_NAME_CONTAINS, len(excluded)))
    print()

    if not failing:
        print("OK: all {} checked tests have the required labels.".format(checked))
        return 0

    print("Tests missing required labels:")
    print()
    for full_name, name in failing:
        missing = missing_by_test[(full_name, name)]
        print("  " + (full_name or "-"))
        print("    name:    " + (name or "-"))
        print("    missing: " + ", ".join(label for label in required if label in missing))
        print()
    print("FAILED: {} of {} checked tests are missing required labels."
          .format(len(failing), checked))
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        # An unexpected failure must not look like exit code 1, "tests are missing labels".
        fail("unexpected error: {!r}".format(error))

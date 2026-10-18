package com.example.billing;

import io.qameta.allure.Epic;
import io.qameta.allure.Feature;
import io.qameta.allure.Owner;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import static org.junit.jupiter.api.Assertions.assertTrue;

@Epic("Billing")
class LabelsContractTest {

    private static int flakyCalls;

    @Test
    @Feature("Tariffs")
    @Owner("ivanov")
    void allLabels() {
    }

    @Test
    @Feature("Tariffs")
    void noOwner() {
    }

    @Test
    @Feature("")
    @Owner("ivanov")
    void emptyFeature() {
    }

    @Test
    @DisplayName("checkAllureReport")
    void allureInDisplayName() {
    }

    @Test
    @DisplayName("display name without the word")
    void allureInMethodNameOnly() {
    }

    @Test
    void allureInMethodName() {
    }

    @ParameterizedTest
    @ValueSource(strings = {"a", "b"})
    @Feature("Tariffs")
    void parameterized(String value) {
    }

    @Test
    @Disabled("contract check")
    void disabled() {
    }

    @Test
    @Feature("Tariffs")
    void flaky() {
        flakyCalls++;
        assertTrue(flakyCalls > 1);
    }
}

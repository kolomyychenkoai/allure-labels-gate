const { epic, feature, owner } = require("allure-js-commons");

jest.retryTimes(1);
let flakyCalls = 0;

describe("billing", () => {
  it("all labels", async () => {
    await epic("Billing");
    await feature("Tariffs");
    await owner("ivanov");
  });

  it("no owner", async () => {
    await epic("Billing");
    await feature("Tariffs");
  });

  it("empty feature", async () => {
    await epic("Billing");
    await feature("");
    await owner("ivanov");
  });

  it("checkAllureReport", async () => {});

  it.each(["a", "b"])("parameterized %s", async () => {
    await epic("Billing");
  });

  it.skip("skipped", async () => {});

  it("flaky", async () => {
    await epic("Billing");
    flakyCalls++;
    expect(flakyCalls).toBeGreaterThan(1);
  });
});

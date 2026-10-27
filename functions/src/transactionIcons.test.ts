import assert from "node:assert/strict";
import {describe, it} from "node:test";

import {
  normalizeTransactionIconAsset,
  SUPPORTED_TRANSACTION_ICON_ASSETS,
  withTransactionIcon,
} from "./transactionIcons.js";

describe("transaction icons", () => {
  it("accepts every supported Material icon", () => {
    const materialIcons = [...SUPPORTED_TRANSACTION_ICON_ASSETS]
      .filter((value) => value.startsWith("material:"));

    for (const icon of materialIcons) {
      assert.equal(normalizeTransactionIconAsset(icon), icon);
    }
  });

  it("accepts legacy PNG asset paths", () => {
    const icon = "assets/images/icons_bills/electricity.png";
    assert.equal(normalizeTransactionIconAsset(icon), icon);
  });

  it("rejects unknown Material and asset values", () => {
    assert.throws(
      () => normalizeTransactionIconAsset("material:not_a_real_icon"),
      /Unsupported iconAsset/,
    );
    assert.throws(
      () => normalizeTransactionIconAsset(
        "assets/images/icons_bills/nope.png",
      ),
      /Unsupported iconAsset/,
    );
  });

  it("includes the validated icon in transaction write data", () => {
    const data = withTransactionIcon(
      {title: "Power", amount: 500},
      normalizeTransactionIconAsset("material:electric_bolt"),
    );

    assert.equal(data.iconAsset, "material:electric_bolt");
  });
});

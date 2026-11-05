import assert from "node:assert/strict";
import {describe, it} from "node:test";

import {
  applySavingsTransfer,
  MAX_SAVINGS_TRANSFER_PARTS,
  parseSavingsTransferPayload,
  reverseSavingsTransfer,
} from "./savingsTransfer";

const wallet = () => ({
  cashAmount: 100,
  currency: "PHP",
  cards: [
    {id: "bdo", iconAsset: "bdo.png", amount: 200},
    {id: "gcash", iconAsset: "gcash.png", amount: 50},
  ],
  loans: [],
});

const part = (
  locationType: "wallet" | "card",
  amount: number,
  cardId?: string,
  cardName = locationType === "wallet" ? "Wallet" : cardId!,
) => ({locationType, amount, cardId, cardName});

describe("savings transfer payload", () => {
  it("accepts valid even and uneven centavo allocations", () => {
    const parsed = parseSavingsTransferPayload({
      savingsSources: [part("wallet", 33.34), part("card", 66.66, "bdo")],
      savingsDestinations: [
        part("wallet", 33.34),
        part("card", 33.33, "bdo"),
        part("card", 33.33, "gcash"),
      ],
    }, 100);
    assert.equal(parsed?.sources.length, 2);
    assert.equal(parsed?.destinations.length, 3);
  });

  it("keeps omitted lists backward compatible", () => {
    assert.equal(parseSavingsTransferPayload({}, 100), undefined);
  });

  it("rejects missing, oversized, invalid, and mismatched payloads", () => {
    assert.throws(() => parseSavingsTransferPayload({
      savingsSources: [part("wallet", 100)],
    }, 100));
    assert.throws(() => parseSavingsTransferPayload({
      savingsSources: Array.from(
        {length: MAX_SAVINGS_TRANSFER_PARTS + 1},
        (_, i) => part("card", 1, `card-${i}`),
      ),
      savingsDestinations: [part("wallet", 11)],
    }, 11));
    assert.throws(() => parseSavingsTransferPayload({
      savingsSources: [part("wallet", Number.NaN)],
      savingsDestinations: [part("card", 1, "bdo")],
    }, 1));
    assert.throws(() => parseSavingsTransferPayload({
      savingsSources: [part("wallet", 99)],
      savingsDestinations: [part("card", 100, "bdo")],
    }, 100));
  });
});

describe("savings transfer balances", () => {
  it("handles a single source and destination atomically", () => {
    const transfer = parseSavingsTransferPayload({
      savingsSources: [part("wallet", 25)],
      savingsDestinations: [part("card", 25, "gcash", "GCash")],
    }, 25)!;
    const changed = applySavingsTransfer(wallet(), transfer);
    assert.equal(changed.cashAmount, 75);
    assert.equal((changed.cards as Array<{id: string; amount: number}>)[1].amount, 75);
    const reversed = reverseSavingsTransfer(changed, transfer);
    assert.equal(reversed.wallet.cashAmount, 100);
    assert.equal(
      (reversed.wallet.cards as Array<{id: string; amount: number}>)[1].amount,
      50,
    );
  });

  it("nets the same location on both sides", () => {
    const transfer = parseSavingsTransferPayload({
      savingsSources: [part("wallet", 100)],
      savingsDestinations: [part("wallet", 100)],
    }, 100)!;
    assert.equal(applySavingsTransfer(wallet(), transfer).cashAmount, 100);
  });

  it("rejects unknown cards and insufficient source balances", () => {
    const unknown = parseSavingsTransferPayload({
      savingsSources: [part("card", 10, "missing")],
      savingsDestinations: [part("wallet", 10)],
    }, 10)!;
    assert.throws(() => applySavingsTransfer(wallet(), unknown));
    const insufficient = parseSavingsTransferPayload({
      savingsSources: [part("wallet", 100.01)],
      savingsDestinations: [part("card", 100.01, "bdo")],
    }, 100.01)!;
    assert.throws(() => applySavingsTransfer(wallet(), insufficient));
  });

  it("rejects malformed wallet card data instead of dropping it", () => {
    const transfer = parseSavingsTransferPayload({
      savingsSources: [part("wallet", 10)],
      savingsDestinations: [part("card", 10, "bdo")],
    }, 10)!;
    assert.throws(() => applySavingsTransfer({
      cashAmount: 100,
      cards: [{id: "bdo", amount: "not-a-number"}],
    }, transfer));
  });

  it("uses Wallet when a card was deleted before undo", () => {
    const transfer = parseSavingsTransferPayload({
      savingsSources: [part("card", 20, "bdo", "BDO")],
      savingsDestinations: [part("card", 20, "gcash", "GCash")],
    }, 20)!;
    const changed = applySavingsTransfer(wallet(), transfer);
    changed.cards = (changed.cards as Array<{id: string}>).filter(
      (card) => card.id !== "bdo",
    );
    const reversed = reverseSavingsTransfer(changed, transfer);
    assert.equal(reversed.fallbacks.length, 1);
    assert.equal(reversed.wallet.cashAmount, 120);
  });
});

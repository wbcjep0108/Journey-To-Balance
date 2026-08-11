import assert from "node:assert/strict";
import {describe, it} from "node:test";

import {
  distributeAddedFunds,
  parseBudget,
  reallocateAllFromAvailableBalance,
  migrateBudgetSchemaIfNeeded,
} from "./budgetMath.js";
import {nextRateBucket, RATE_LIMITS, WINDOW_MS} from "./rateLimit.js";
import {HttpsError} from "firebase-functions/v2/https";

describe("budgetMath", () => {
  it("distributes only new money by user percentages", () => {
    const budget = parseBudget({
      availableBalance: 12000,
      billsPercentage: 50,
      personalPercentage: 40,
      savingsPercentage: 10,
      billsRemaining: 6000,
      personalRemaining: 4800,
      savingsRemaining: 1200,
      schemaVersion: 3,
    });
    budget.availableBalance += 500;
    distributeAddedFunds(budget, 500);
    assert.equal(budget.billsRemaining, 6250);
    assert.equal(budget.personalRemaining, 5000);
    assert.equal(budget.savingsRemaining, 1250);
  });

  it("reallocates all categories from new available balance", () => {
    const budget = parseBudget({
      availableBalance: 11000,
      billsPercentage: 50,
      personalPercentage: 40,
      savingsPercentage: 10,
      billsRemaining: 5000,
      personalRemaining: 4800,
      savingsRemaining: 1200,
      schemaVersion: 3,
    });
    budget.availableBalance = 7000;
    reallocateAllFromAvailableBalance(budget);
    assert.equal(budget.billsRemaining, 3500);
    assert.equal(budget.personalRemaining, 2800);
    assert.equal(budget.savingsRemaining, 700);
  });

  it("uses custom user percentages", () => {
    const budget = parseBudget({
      availableBalance: 10000,
      billsPercentage: 30,
      personalPercentage: 50,
      savingsPercentage: 20,
      schemaVersion: 3,
    });
    reallocateAllFromAvailableBalance(budget);
    assert.equal(budget.billsRemaining, 3000);
    assert.equal(budget.personalRemaining, 5000);
    assert.equal(budget.savingsRemaining, 2000);
  });

  it("migrates missing remainings", () => {
    const budget = parseBudget({
      availableBalance: 1000,
      billsPercentage: 50,
      personalPercentage: 40,
      savingsPercentage: 10,
      billsRemaining: 0,
      personalRemaining: 0,
      savingsRemaining: 0,
      schemaVersion: 2,
    });
    const migrated = migrateBudgetSchemaIfNeeded(budget);
    assert.equal(migrated, true);
    assert.equal(budget.schemaVersion, 3);
    assert.equal(budget.billsRemaining, 500);
  });
});

describe("rateLimit", () => {
  it("allows requests under the limit", () => {
    let state = nextRateBucket(undefined, 3, 1000);
    state = nextRateBucket(state, 3, 1001);
    state = nextRateBucket(state, 3, 1002);
    assert.equal(state.count, 3);
  });

  it("rejects when the limit is exceeded", () => {
    let state = nextRateBucket(undefined, 2, 1000);
    state = nextRateBucket(state, 2, 1001);
    assert.throws(
      () => nextRateBucket(state, 2, 1002),
      (error: unknown) =>
        error instanceof HttpsError && error.code === "resource-exhausted",
    );
  });

  it("resets after the window", () => {
    const state = nextRateBucket(
      {count: 10, windowStart: 1000},
      10,
      1000 + WINDOW_MS,
    );
    assert.equal(state.count, 1);
  });

  it("exposes expected limit values", () => {
    assert.equal(RATE_LIMITS.general, 60);
    assert.equal(RATE_LIMITS.receiveSalary, 10);
    assert.equal(RATE_LIMITS.addTransaction, 30);
  });
});

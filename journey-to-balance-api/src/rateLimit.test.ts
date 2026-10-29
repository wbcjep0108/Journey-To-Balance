import assert from "node:assert/strict";
import {describe, it} from "node:test";

import {ApiError} from "./errors";
import {
  consumeFixedWindow,
  nextRateBucket,
  RATE_LIMITS,
  WINDOW_MS,
} from "./rateLimit";

describe("nextRateBucket over-limit", () => {
  it("throws ApiError 429 when count reaches the limit", () => {
    const limit = RATE_LIMITS.rateLimitTest;
    let state = nextRateBucket(undefined, limit, 1000);
    for (let i = 1; i < limit; i++) {
      state = nextRateBucket(state, limit, 1000 + i);
    }
    assert.equal(state.count, limit);
    assert.throws(
      () => nextRateBucket(state, limit, 1000 + limit),
      (error: unknown) =>
        error instanceof ApiError && error.status === 429,
    );
  });

  it("resets after the window so a new request is allowed", () => {
    const next = nextRateBucket(
      {count: 5, windowStart: 1000},
      5,
      1000 + WINDOW_MS,
    );
    assert.equal(next.count, 1);
  });
});

describe("password reset fixed-window limits", () => {
  it("allows three requests per hour and rejects the fourth", () => {
    const hour = 60 * 60 * 1000;
    let state;
    for (let count = 0; count < 3; count++) {
      const outcome = consumeFixedWindow(state, 3, hour, 1000 + count);
      assert.equal(outcome.allowed, true);
      state = outcome.state;
    }
    assert.equal(consumeFixedWindow(state, 3, hour, 2000).allowed, false);
    assert.equal(
      consumeFixedWindow(state, 3, hour, hour + 1000).allowed,
      true,
    );
  });
});

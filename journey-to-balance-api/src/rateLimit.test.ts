import assert from "node:assert/strict";
import {describe, it} from "node:test";

import {ApiError} from "./errors";
import {nextRateBucket, RATE_LIMITS, WINDOW_MS} from "./rateLimit";

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

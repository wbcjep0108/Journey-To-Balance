import assert from "node:assert/strict";
import {describe, it} from "node:test";

import {buildPinResetEmailHtml} from "./pinResetEmail";

describe("buildPinResetEmailHtml", () => {
  it("renders a branded, mobile-friendly PIN reset email", () => {
    const html = buildPinResetEmailHtml("9877");

    assert.match(html, /<!doctype html>/i);
    assert.match(html, /Journey to Balance/);
    assert.match(html, /Reset your PIN/);
    assert.match(html, /9877/);
    assert.match(html, /Expires in 10 minutes/);
    assert.match(html, /viewport/);
  });
});

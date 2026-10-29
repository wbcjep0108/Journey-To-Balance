import assert from "node:assert/strict";
import {describe, it} from "node:test";

import {renderPasswordResetEmail} from "./passwordResetEmail";

describe("renderPasswordResetEmail", () => {
  it("renders the subject, code, expiry, text, and matching branded HTML", () => {
    const result = renderPasswordResetEmail({code: "123456", minutes: 10});
    assert.equal(result.subject, "Your Journey to Balance password reset code");
    assert.match(result.text, /123456/);
    assert.match(result.text, /10 minutes/);
    assert.match(result.html, />123456</);
    assert.match(result.html, /10 minutes/);
    assert.match(result.html, /Never share this code/);
    assert.match(result.html, /Didn&#39;t ask/);
  });

  it("rejects values that could escape the template", () => {
    assert.throws(() => renderPasswordResetEmail({code: "<12345", minutes: 10}));
    assert.throws(() => renderPasswordResetEmail({code: "123456", minutes: 0}));
    assert.throws(() => renderPasswordResetEmail({code: "123456", minutes: 1.5}));
  });

  it("has no external stylesheet, script, or remote image", () => {
    const {html} = renderPasswordResetEmail({code: "654321", minutes: 10});
    assert.doesNotMatch(html, /<script\b/i);
    assert.doesNotMatch(html, /<link\b/i);
    assert.doesNotMatch(html, /<img\b/i);
    assert.doesNotMatch(html, /url\s*\(/i);
  });
});

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  extractBearerToken,
  resolveAuthenticatedUser,
  decideRateLimit,
  RateLimitResponseError,
  RATE_LIMIT_WINDOW_SECONDS,
} from "./access.ts";

test("extractBearerToken returns the token from a Bearer header", () => {
  assert.equal(extractBearerToken("Bearer abc.def.ghi"), "abc.def.ghi");
  assert.equal(extractBearerToken("bearer abc"), "abc");
});

test("extractBearerToken rejects missing or malformed headers", () => {
  assert.equal(extractBearerToken(null), null);
  assert.equal(extractBearerToken(""), null);
  assert.equal(extractBearerToken("Bearer"), null);
  assert.equal(extractBearerToken("Basic abc"), null);
  assert.equal(extractBearerToken("Bearer a b"), null);
});

test("resolveAuthenticatedUser accepts an authenticated user", () => {
  const result = { data: { user: { id: "u-1", role: "authenticated" } }, error: null };
  assert.deepEqual(resolveAuthenticatedUser(result), { userId: "u-1" });
});

test("resolveAuthenticatedUser rejects the anon key (no user)", () => {
  assert.equal(
    resolveAuthenticatedUser({ data: { user: null }, error: { message: "missing sub claim" } }),
    null,
  );
  assert.equal(resolveAuthenticatedUser({ data: { user: null }, error: null }), null);
  assert.equal(resolveAuthenticatedUser({ data: null, error: null }), null);
});

test("resolveAuthenticatedUser rejects a user with no id or a non-authenticated role", () => {
  assert.equal(resolveAuthenticatedUser({ data: { user: { role: "authenticated" } }, error: null }), null);
  assert.equal(resolveAuthenticatedUser({ data: { user: { id: "", role: "authenticated" } }, error: null }), null);
  assert.equal(resolveAuthenticatedUser({ data: { user: { id: "u-1", role: "anon" } }, error: null }), null);
  assert.equal(resolveAuthenticatedUser({ data: { user: { id: "u-1" } }, error: null }), null);
});

test("resolveAuthenticatedUser rejects when getUser reports an error", () => {
  const result = { data: { user: { id: "u-1", role: "authenticated" } }, error: new Error("bad jwt") };
  assert.equal(resolveAuthenticatedUser(result), null);
});

test("decideRateLimit allows a request under the limit", () => {
  assert.deepEqual(decideRateLimit([{ allowed: true, retry_after_seconds: 0 }]), { allowed: true });
  assert.deepEqual(decideRateLimit({ allowed: true }), { allowed: true });
});

test("decideRateLimit denies with a retry-after rounded up to at least 1 second", () => {
  assert.deepEqual(
    decideRateLimit([{ allowed: false, retry_after_seconds: 42.2 }]),
    { allowed: false, retryAfterSeconds: 43 },
  );
  assert.deepEqual(
    decideRateLimit([{ allowed: false, retry_after_seconds: 0 }]),
    { allowed: false, retryAfterSeconds: 1 },
  );
});

test("decideRateLimit falls back to the full window when retry-after is unusable", () => {
  assert.deepEqual(
    decideRateLimit([{ allowed: false }]),
    { allowed: false, retryAfterSeconds: RATE_LIMIT_WINDOW_SECONDS },
  );
});

test("decideRateLimit fails closed on a malformed RPC response", () => {
  assert.throws(() => decideRateLimit(null), RateLimitResponseError);
  assert.throws(() => decideRateLimit([]), RateLimitResponseError);
  assert.throws(() => decideRateLimit([{ retry_after_seconds: 5 }]), RateLimitResponseError);
  assert.throws(() => decideRateLimit([{ allowed: "yes" }]), RateLimitResponseError);
});

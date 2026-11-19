// Pure auth and rate-limit decisions for the `google-tts` Edge Function, kept
// free of Deno/network APIs so they can be unit-tested with Node (see
// access.test.ts). `index.ts` performs the Supabase calls and feeds the
// results through these functions.

export const RATE_LIMIT_MAX_REQUESTS = 30;
export const RATE_LIMIT_WINDOW_SECONDS = 600;

export class RateLimitResponseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RateLimitResponseError";
  }
}

export function extractBearerToken(header: string | null): string | null {
  const match = /^Bearer\s+(\S+)$/i.exec(header ?? "");
  return match ? match[1] : null;
}

/**
 * Accepts the result of `supabase.auth.getUser(token)`. The public anon key
 * is a validly signed JWT but resolves to no user (or role "anon"), so it
 * is rejected here.
 */
export function resolveAuthenticatedUser(
  result: { data: { user: unknown } | null; error: unknown },
): { userId: string } | null {
  if (result.error || !result.data) return null;
  const user = result.data.user as { id?: unknown; role?: unknown } | null;
  if (!user || typeof user.id !== "string" || user.id.length === 0) return null;
  if (user.role !== "authenticated") return null;
  return { userId: user.id };
}

export type RateLimitDecision =
  | { allowed: true }
  | { allowed: false; retryAfterSeconds: number };

/**
 * Interprets the row returned by the `consume_tts_rate_limit` RPC
 * (`allowed boolean, retry_after_seconds integer`). Anything malformed
 * throws, so the caller fails closed instead of skipping the limit.
 */
export function decideRateLimit(rpcData: unknown): RateLimitDecision {
  const row = Array.isArray(rpcData) ? rpcData[0] : rpcData;
  if (typeof row !== "object" || row === null) {
    throw new RateLimitResponseError("Rate limit RPC returned no row");
  }
  const { allowed, retry_after_seconds: retryAfter } = row as Record<string, unknown>;
  if (typeof allowed !== "boolean") {
    throw new RateLimitResponseError("Rate limit RPC row is missing `allowed`");
  }
  if (allowed) return { allowed: true };
  const seconds = typeof retryAfter === "number" && Number.isFinite(retryAfter)
    ? Math.max(1, Math.ceil(retryAfter))
    : RATE_LIMIT_WINDOW_SECONDS;
  return { allowed: false, retryAfterSeconds: seconds };
}

// Supabase Edge Function: synthesizes AI chat replies into speech via
// Google Cloud Text-to-Speech, so the Google service-account credential
// never has to live in the Flutter app. The gateway JWT check is disabled for
// this function (see supabase/config.toml), so this code is the only gate: it
// resolves the bearer token to a signed-in user and applies a per-user rate
// limit.
import { GoogleAuth } from "npm:google-auth-library@10.9.0";
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

import {
  SYNTHESIZE_URL,
  parseTtsRequest,
  buildSynthesizeRequestBody,
  extractAudioContent,
  InvalidTtsRequestError,
  GoogleTtsResponseError,
} from "./request.ts";
import {
  RATE_LIMIT_MAX_REQUESTS,
  RATE_LIMIT_WINDOW_SECONDS,
  RateLimitResponseError,
  extractBearerToken,
  resolveAuthenticatedUser,
  decideRateLimit,
} from "./access.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "private, no-store",
      ...CORS_HEADERS,
      ...init.headers,
    },
  });
}

// The service-account JSON and any voice override are read once per cold
// start, not per request — neither ever leaves this server-side function.
const credentialsJson = Deno.env.get("GOOGLE_TTS_CREDENTIALS");
const voiceOverride = Deno.env.get("GOOGLE_TTS_VOICE_ID");

// SUPABASE_URL and the secret key are injected by the platform. Projects with
// the new API keys get SUPABASE_SECRET_KEYS (a JSON object; the key created
// by default is named "default"); older projects get the plain
// SUPABASE_SERVICE_ROLE_KEY string.
function getSecretKey(): string {
  const keys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (keys) {
    const key = JSON.parse(keys)["default"];
    if (typeof key === "string" && key.length > 0) return key;
  }
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  throw new Error("No Supabase secret key is configured");
}

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  getSecretKey(),
  { auth: { persistSession: false, autoRefreshToken: false } },
);

let cachedAuth: GoogleAuth | null = null;

function getAuth(): GoogleAuth {
  if (cachedAuth) return cachedAuth;
  if (!credentialsJson) {
    throw new Error("GOOGLE_TTS_CREDENTIALS is not configured");
  }
  cachedAuth = new GoogleAuth({
    credentials: JSON.parse(credentialsJson),
    scopes: ["https://www.googleapis.com/auth/cloud-platform"],
  });
  return cachedAuth;
}

async function getAccessToken(): Promise<string> {
  const client = await getAuth().getClient();
  const token = await client.getAccessToken();
  if (!token.token) {
    throw new Error("Failed to obtain a Google access token");
  }
  return token.token;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, { status: 405 });
  }

  const token = extractBearerToken(req.headers.get("Authorization"));
  const user = token ? resolveAuthenticatedUser(await supabase.auth.getUser(token)) : null;
  if (!user) {
    return jsonResponse({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { data, error } = await supabase.rpc("consume_tts_rate_limit", {
      p_user_id: user.userId,
      p_limit: RATE_LIMIT_MAX_REQUESTS,
      p_window_seconds: RATE_LIMIT_WINDOW_SECONDS,
    });
    if (error) throw error;
    const decision = decideRateLimit(data);
    if (!decision.allowed) {
      return jsonResponse(
        { error: "Too many requests" },
        { status: 429, headers: { "Retry-After": String(decision.retryAfterSeconds) } },
      );
    }
  } catch (error) {
    if (!(error instanceof RateLimitResponseError)) {
      console.error("Rate limit check failed", error);
    } else {
      console.error(error.message);
    }
    return jsonResponse({ error: "Internal error" }, { status: 500 });
  }

  let payload: unknown;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: "Request body must be valid JSON" }, { status: 400 });
  }

  let ttsRequest;
  try {
    ttsRequest = parseTtsRequest(payload);
  } catch (error) {
    if (error instanceof InvalidTtsRequestError) {
      return jsonResponse({ error: error.message }, { status: 400 });
    }
    throw error;
  }

  try {
    const accessToken = await getAccessToken();
    const response = await fetch(SYNTHESIZE_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(buildSynthesizeRequestBody(ttsRequest, voiceOverride)),
    });

    if (!response.ok) {
      const detail = await response.text();
      console.error("Google TTS request failed", response.status, detail);
      return jsonResponse({ error: "Speech synthesis failed upstream" }, { status: 502 });
    }

    const audioContent = extractAudioContent(await response.json());
    return jsonResponse({ audioContent });
  } catch (error) {
    if (error instanceof GoogleTtsResponseError) {
      console.error("Google TTS returned an unusable response", error.message);
      return jsonResponse({ error: "Speech synthesis failed upstream" }, { status: 502 });
    }
    console.error("Unexpected google-tts failure", error);
    return jsonResponse({ error: "Internal error" }, { status: 500 });
  }
});

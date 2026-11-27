import "server-only";

import { createHash, createHmac } from "node:crypto";
import { isIP } from "node:net";
import { createClient } from "@supabase/supabase-js";
import { getSupabaseConfig } from "../supabase/config";

export function bookingClient() {
  const { url } = getSupabaseConfig();
  const key = process.env.SUPABASE_SECRET_KEY?.trim();
  if (!key?.startsWith("sb_secret_")) throw new Error("예약 서버 설정을 확인해 주세요.");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      fetch: (input, init) => fetch(input, { ...init, cache: "no-store", signal: AbortSignal.timeout(8000) }),
    },
  });
}

export function hashToken(token: string) {
  return createHash("sha256").update(Buffer.from(token, "hex")).digest("hex");
}

export function clientBucket(request: Request) {
  const header = process.env.BOOKING_TRUSTED_IP_HEADER?.trim().toLowerCase();
  const secret = process.env.SUPABASE_SECRET_KEY?.trim();
  if (!header || !/^[a-z0-9-]+$/.test(header) || !secret) return null;
  const value = request.headers.get(header)?.trim();
  return value && isIP(value)
    ? createHmac("sha256", secret).update("r5-traffic:").update(value).digest("hex")
    : null;
}

import "server-only";

import { cookies } from "next/headers";

export const challengeCookie = "teum-email-challenge";

type ChallengeType = "email" | "recovery";

export function parseChallenge(type: string | null, token: string | null) {
  if ((type !== "email" && type !== "recovery") || !token || !/^[A-Za-z0-9_-]{32,256}$/.test(token)) {
    return null;
  }
  return { type, token };
}

export const challengeCookieOptions = {
  httpOnly: true,
  sameSite: "lax",
  secure: process.env.NODE_ENV === "production",
  path: "/auth",
  maxAge: 600,
} as const;

export async function readChallenge(type: ChallengeType) {
  const value = (await cookies()).get(challengeCookie)?.value ?? "";
  const [storedType, token, extra] = value.split(":");
  const challenge = extra === undefined ? parseChallenge(storedType, token) : null;
  return challenge?.type === type ? challenge.token : null;
}

export async function clearChallenge() {
  (await cookies()).set(challengeCookie, "", { ...challengeCookieOptions, maxAge: 0 });
}

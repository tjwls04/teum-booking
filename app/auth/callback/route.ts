import { type NextRequest, NextResponse } from "next/server";
import { challengeCookie, challengeCookieOptions, parseChallenge } from "../../../lib/auth/challenge";

export function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const types = params.getAll("type");
  const tokens = params.getAll("token_hash");
  const challenge = types.length === 1 && tokens.length === 1
    ? parseChallenge(types[0], tokens[0])
    : null;

  let location = "/auth/link-invalid";
  if (challenge) {
    location = challenge.type === "email" ? "/auth/confirm" : "/auth/reset-password";
  }

  const response = new NextResponse(null, {
    status: 303,
    headers: {
      Location: location,
      "Cache-Control": "private, no-store",
      "Referrer-Policy": "no-referrer",
    },
  });
  if (challenge) {
    response.cookies.set(challengeCookie, `${challenge.type}:${challenge.token}`, challengeCookieOptions);
  }
  return response;
}

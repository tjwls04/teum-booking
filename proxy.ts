import { createServerClient } from "@supabase/ssr";
import { type NextRequest, NextResponse } from "next/server";
import { notificationPath } from "./lib/notifications/types";
import { getSupabaseConfig } from "./lib/supabase/config";
import { sessionCookieOptions } from "./lib/supabase/server";

export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  const { url, publishableKey } = getSupabaseConfig();
  const supabase = createServerClient(url, publishableKey, {
    cookieOptions: sessionCookieOptions,
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(cookiesToSet, cacheHeaders) {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value);
        }

        const previous = response;
        response = NextResponse.next({ request });
        for (const cookie of previous.cookies.getAll()) {
          response.cookies.set(cookie);
        }
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
        for (const name of ["cache-control", "expires", "pragma"]) {
          const value = cacheHeaders[name] ?? previous.headers.get(name);
          if (value) response.headers.set(name, value);
        }
      },
    },
  });

  const { data } = await supabase.auth.getClaims();
  const path = request.nextUrl.pathname;
  const notificationId = path.split("/").at(-1) ?? "";
  if (!data?.claims && path === notificationPath(notificationId)) {
    const url = new URL("/auth/login", request.url);
    url.searchParams.set("notification", notificationId);
    const login = NextResponse.redirect(url);
    for (const cookie of response.cookies.getAll()) login.cookies.set(cookie);
    response = login;
  }
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}

export const config = { matcher: "/dashboard/:path*" };

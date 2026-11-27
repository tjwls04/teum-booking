// Direct property access lets Next.js inline these public settings in client bundles.
export function getSupabaseConfig() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();

  if (!url || !publishableKey) {
    throw new Error("NEXT_PUBLIC_SUPABASE_URL과 NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY를 설정하세요.");
  }

  if (!publishableKey.startsWith("sb_publishable_")) {
    throw new Error("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY에는 Supabase publishable key를 설정하세요.");
  }

  let parsedUrl: URL;
  try {
    parsedUrl = new URL(url);
  } catch {
    throw new Error("NEXT_PUBLIC_SUPABASE_URL에 올바른 Supabase 프로젝트 URL을 설정하세요.");
  }

  if (
    !["http:", "https:"].includes(parsedUrl.protocol) ||
    parsedUrl.username ||
    parsedUrl.password ||
    parsedUrl.search ||
    parsedUrl.hash
  ) {
    throw new Error("NEXT_PUBLIC_SUPABASE_URL에 올바른 Supabase 프로젝트 URL을 설정하세요.");
  }

  if (
    ["supabase.com", "www.supabase.com"].includes(parsedUrl.hostname) ||
    (parsedUrl.hostname.endsWith(".supabase.co") && parsedUrl.pathname !== "/")
  ) {
    throw new Error("NEXT_PUBLIC_SUPABASE_URL에는 Supabase Connect의 Project URL을 설정하세요.");
  }

  return { url: parsedUrl.href, publishableKey };
}

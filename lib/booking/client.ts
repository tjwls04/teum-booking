type Result<T> = { ok: true; data: T } | { ok: false; code: string; message: string };

export async function bookingRequest<T>(operation: string, body: object, token?: string): Promise<Result<T>> {
  const unavailable = { ok: false, code: "unavailable", message: "응답을 확인하지 못했어요. 잠시 뒤 다시 시도해 주세요." } as const;
  try {
    const response = await fetch(`/api/booking/${operation}`, {
      method: "POST",
      cache: "no-store",
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(20000),
    });
    const data = await response.json();
    if (response.ok) return { ok: true, data };
    if (typeof data?.code === "string" && typeof data?.message === "string") {
      return { ok: false, code: data.code, message: data.message };
    }
    return unavailable;
  } catch {
    return unavailable;
  }
}

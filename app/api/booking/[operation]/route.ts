import { bookingClient, clientBucket, hashToken } from "../../../../lib/booking/server";
import { validSlug, validToken } from "../../../../lib/booking/types";
import { isUuid } from "../../../../lib/dashboard/settings";

const errors: Record<string, string> = {
  r5_input: "예약 정보를 다시 확인해 주세요.",
  r5_time: "선택한 시간은 예약할 수 없어요. 가능한 시간을 다시 확인해 주세요.",
  r5_revision: "시술 또는 예약 조건이 변경됐어요. 최신 조건을 다시 확인해 주세요.",
  r5_key: "이 요청에 이미 다른 예약 정보가 기록됐어요.",
  r5_conflict: "동시에 다른 요청이 처리됐어요. 예약 결과와 시간을 다시 확인해 주세요.",
  r5_missing: "예약 정보를 찾을 수 없어요.",
  rate_limit: "요청이 많아요. 잠시 뒤 같은 요청을 다시 시도해 주세요.",
  unavailable: "예약 서버 응답을 확인하지 못했어요. 잠시 뒤 다시 시도해 주세요.",
};

function json(body: unknown, status = 200) {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "private, no-store", "Referrer-Policy": "no-referrer" },
  });
}

function fail(code: string, status: number) {
  return json({ code, message: errors[code] }, status);
}

async function readBody(request: Request): Promise<Record<string, unknown> | null> {
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json" || !request.body) return null;
  if (Number(request.headers.get("content-length")) > 4096) return null;
  const reader = request.body.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let total = 0;
  let text = "";
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      total += part.value.byteLength;
      if (total > 4096) {
        await reader.cancel();
        return null;
      }
      text += decoder.decode(part.value, { stream: true });
    }
    const data: unknown = JSON.parse(text + decoder.decode());
    return data && typeof data === "object" && !Array.isArray(data) ? data as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

function exactDate(value: unknown): value is string {
  if (typeof value !== "string" || !/^20[0-9]{2}-[0-9]{2}-[0-9]{2}$/.test(value)) return false;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

function revision(value: unknown) {
  return typeof value === "number" && Number.isInteger(value) && value >= 1 && value <= 2_147_483_647;
}

function validSelection(body: Record<string, unknown>) {
  return typeof body.service === "string" && isUuid(body.service) && revision(body.revision) && revision(body.policy);
}

function sameOrigin(request: Request) {
  const origin = process.env.BOOKING_APP_ORIGIN?.trim() || new URL(request.url).origin;
  return request.headers.get("origin") === origin && request.headers.get("sec-fetch-site") !== "cross-site";
}

export async function POST(request: Request, { params }: RouteContext<"/api/booking/[operation]">) {
  const { operation } = await params;
  if (!["catalog", "slots", "create", "confirm", "report"].includes(operation)) return fail("r5_missing", 404);
  if (!sameOrigin(request)) return fail("r5_input", 403);
  const body = await readBody(request);
  if (!body) return fail("r5_input", 400);

  const isConfirm = operation === "confirm" || operation === "report";
  const slug = isConfirm ? "confirmation" : body.slug;
  const token = request.headers.get("authorization")?.match(/^Bearer ([a-f0-9]{64})$/)?.[1];
  if (!validSlug(slug) || ((operation === "create" || isConfirm) && !validToken(token))) return fail("r5_input", 400);
  if ((operation === "slots" || operation === "create") && !validSelection(body)) return fail("r5_input", 400);
  if (operation === "slots" && !exactDate(body.day)) return fail("r5_input", 400);
  if (operation === "create" && (
    typeof body.start !== "string" || !/^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:00(?:\.000)?(?:Z|[+-][0-9]{2}:[0-9]{2})$/.test(body.start) ||
    !exactDate(body.start.slice(0, 10)) || !Number.isFinite(Date.parse(body.start)) ||
    typeof body.name !== "string" || !body.name.trim() || body.name.trim().length > 60 || /[\p{Cc}]/u.test(body.name) ||
    typeof body.phone !== "string" || body.phone.length > 20 || !/^01[016789][0-9]{7,8}$/.test(body.phone.replace(/[ -]/g, "")) ||
    typeof body.consent !== "string" || !/^[a-z0-9-]{1,40}$/.test(body.consent) ||
    typeof body.key !== "string" || !isUuid(body.key)
  )) return fail("r5_input", 400);

  try {
    const db = bookingClient();
    const tokenHash = token ? hashToken(token) : null;
    const admission = await db.rpc("r9_allow_booking", {
      p_operation: operation, p_slug: isConfirm ? null : slug,
      p_client: clientBucket(request), p_token_hash: tokenHash,
    });
    if (admission.error) return fail("unavailable", 503);
    if (admission.data === "missing") return fail("r5_missing", 404);
    if (admission.data === "limited") return fail("rate_limit", 429);
    if (admission.data !== "allowed") return fail("unavailable", 503);

    let result: { data: unknown; error: { code: string; message: string } | null };
    if (operation === "catalog") {
      result = await db.rpc("r5_catalog", { p_slug: slug });
    } else if (operation === "slots") {
      result = await db.rpc("r5_slots", {
        p_slug: slug, p_service: body.service, p_day: body.day, p_revision: body.revision, p_policy: body.policy,
      });
    } else if (operation === "create") {
      result = await db.rpc("r5_create", {
        p_slug: slug, p_service: body.service, p_start: body.start, p_revision: body.revision, p_policy: body.policy,
        p_name: body.name, p_phone: body.phone, p_consent: body.consent, p_key: body.key, p_token_hash: tokenHash,
      });
    } else {
      result = await db.rpc("r5_confirmation", { p_token_hash: tokenHash, p_report: operation === "report" });
    }
    if (result.error) {
      const { code, message } = result.error;
      if (!Object.hasOwn(errors, message)) return fail("unavailable", 503);
      if (code === "PT409") return fail(message, 409);
      if (code === "PT404") return fail(message, 404);
      if (code === "22023") return fail(message, 400);
      return fail("unavailable", 503);
    }
    return result.data === null ? fail("r5_missing", 404) : json(result.data);
  } catch {
    // The request may have committed before a network timeout. The client keeps the original envelope.
    return fail("unavailable", 503);
  }
}

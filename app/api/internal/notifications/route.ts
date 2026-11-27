import { createHash, timingSafeEqual } from "node:crypto";
import { bookingClient } from "../../../../lib/booking/server";
import { type ClaimedDelivery, deliver, vapidConfig } from "../../../../lib/notifications/push";

export const runtime = "nodejs";
export const maxDuration = 60;

function json(data: object, status = 200) {
  return Response.json(data, { status, headers: { "Cache-Control": "no-store" } });
}

export async function POST(request: Request) {
  const key = process.env.NOTIFICATION_WORKER_KEY?.trim();
  if (!key || key.length < 32) return json({ error: "unavailable" }, 503);
  const authorization = request.headers.get("authorization") ?? "";
  const hash = (value: string) => createHash("sha256").update(value).digest();
  if (!timingSafeEqual(hash(authorization), hash(`Bearer ${key}`))) return json({ error: "unauthorized" }, 401);

  try {
    const supabase = bookingClient();
    const scan = await supabase.rpc("r8_scan");
    if (scan.error) return json({ error: "scan_failed" }, 503);

    const vapid = vapidConfig();
    if (!vapid) return json({ error: "push_unconfigured" }, 503);
    const { data, error } = await supabase.rpc("r8_claim");
    if (error || !Array.isArray(data)) return json({ error: "claim_failed" }, 503);
    const jobs = data as ClaimedDelivery[];

    // Keep each batch inside the Cron HTTP timeout even if several providers are slow.
    const results = await Promise.allSettled(jobs.map(async (job) => {
      const result = await deliver(job, vapid);
      const completion = await supabase.rpc("r8_finish", {
        p_id: job.id, p_lease: job.lease_token, p_result: result.result,
        p_error: result.error, p_retry_seconds: result.retrySeconds ?? null,
      });
      return !completion.error && completion.data === true;
    }));
    const unrecorded = results.filter((item) => item.status === "rejected" || !item.value).length;
    return json({ claimed: jobs.length, unrecorded }, unrecorded ? 503 : 200);
  } catch {
    return json({ error: "worker_failed" }, 503);
  }
}

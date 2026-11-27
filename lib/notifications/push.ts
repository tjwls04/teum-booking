import "server-only";

import { createECDH, createHash, ECDH } from "node:crypto";
import { Resolver } from "node:dns/promises";
import { request } from "node:https";
import { BlockList } from "node:net";
import { generateRequestDetails, getVapidHeaders, type VapidKeys } from "web-push";
import { type NotificationKind, notificationLabels, notificationPath } from "./types";

type VapidDetails = VapidKeys & { subject: string };

const endpointPattern =
  /^https:\/\/(?:fcm\.googleapis\.com\/fcm\/send\/|updates\.push\.services\.mozilla\.com\/wpush\/v[12]\/|(?:[a-z0-9-]+\.)+push\.apple\.com\/)[A-Za-z0-9_~:.-]{8,}$/;

function pushEndpoint(value: unknown) {
  if (typeof value !== "string" || value.length > 1600 || !endpointPattern.test(value)) return null;
  try {
    const url = new URL(value);
    return url.href === value && url.hostname.length <= 253 ? url : null;
  } catch {
    return null;
  }
}

export function validPushEndpoint(value: unknown): value is string {
  return pushEndpoint(value) !== null;
}

function decodeKey(value: unknown, size: number) {
  if (typeof value !== "string" || value.length !== Math.ceil(size * 4 / 3) || !/^[\w-]+$/.test(value)) return null;
  const bytes = Buffer.from(value, "base64url");
  return bytes.length === size && bytes.toString("base64url") === value ? bytes : null;
}

function publicKeyBytes(value: unknown) {
  const bytes = decodeKey(value, 65);
  if (bytes?.[0] !== 4) return null;
  try {
    ECDH.convertKey(bytes, "prime256v1");
    return bytes;
  } catch {
    return null;
  }
}

export function validSubscriptionKeys(p256dh: unknown, auth: unknown) {
  return Boolean(publicKeyBytes(p256dh) && decodeKey(auth, 16));
}

export function vapidConfig(): VapidDetails | null {
  const publicKey = process.env.VAPID_PUBLIC_KEY?.trim();
  const privateKey = process.env.VAPID_PRIVATE_KEY?.trim();
  const subject = process.env.VAPID_SUBJECT?.trim();
  if (!publicKey || !privateKey || !subject) return null;
  const publicBytes = publicKeyBytes(publicKey);
  const privateBytes = decodeKey(privateKey, 32);
  if (!publicBytes || !privateBytes) return null;
  try {
    const curve = createECDH("prime256v1");
    curve.setPrivateKey(privateBytes);
    if (!curve.getPublicKey().equals(publicBytes)) return null;
    getVapidHeaders("https://fcm.googleapis.com", subject, publicKey, privateKey, "aes128gcm");
    return { subject, publicKey, privateKey };
  } catch {
    return null;
  }
}

const blocked = new BlockList();
for (const [address, prefix] of [
  ["0.0.0.0", 8], ["10.0.0.0", 8], ["100.64.0.0", 10], ["127.0.0.0", 8],
  ["169.254.0.0", 16], ["172.16.0.0", 12], ["192.0.0.0", 24], ["192.0.2.0", 24],
  ["192.88.99.0", 24], ["192.168.0.0", 16], ["198.18.0.0", 15], ["198.51.100.0", 24],
  ["203.0.113.0", 24], ["224.0.0.0", 3],
] as const) {
  blocked.addSubnet(address, prefix, "ipv4");
}
const resolver = new Resolver({ timeout: 2200, tries: 1 });

export type ClaimedDelivery = {
  id: string;
  lease_token: string;
  notification_id: string;
  kind: NotificationKind;
  endpoint: string;
  p256dh: string;
  auth_secret: string;
};

type Result = {
  result: "sent" | "retry" | "failed" | "gone";
  error: string | null;
  retrySeconds?: number;
};

function retrySeconds(value: string | undefined) {
  if (!value) return undefined;
  const seconds = /^\d+$/.test(value) ? Number(value) : Math.ceil((Date.parse(value) - Date.now()) / 1000);
  return Number.isFinite(seconds) ? Math.min(3600, Math.max(0, seconds)) : undefined;
}

function send(address: string, endpoint: URL, details: ReturnType<typeof generateRequestDetails>) {
  return new Promise<{ status: number; retryAfter: string | undefined }>((resolve, reject) => {
    // Use the checked address for TCP and preserve the original name for certificate verification and Host.
    const req = request({
      hostname: address,
      servername: endpoint.hostname,
      port: 443,
      path: endpoint.pathname,
      method: "POST",
      headers: { ...details.headers, Host: endpoint.hostname },
      agent: false,
      rejectUnauthorized: true,
      signal: AbortSignal.timeout(6500),
    }, (response) => {
      resolve({ status: response.statusCode ?? 0, retryAfter: response.headers["retry-after"] });
      response.destroy();
    });
    req.once("error", reject);
    req.end(details.body);
  });
}

export async function deliver(job: ClaimedDelivery, vapid: VapidDetails): Promise<Result> {
  const endpoint = pushEndpoint(job.endpoint);
  if (!endpoint || !validSubscriptionKeys(job.p256dh, job.auth_secret)
      || !notificationPath(job.notification_id) || !Object.hasOwn(notificationLabels, job.kind)) {
    return { result: "failed", error: "invalid_subscription" };
  }
  const details = generateRequestDetails(
    { endpoint: endpoint.href, keys: { p256dh: job.p256dh, auth: job.auth_secret } },
    JSON.stringify({ id: job.notification_id, kind: job.kind }),
    { TTL: 900, contentEncoding: "aes128gcm", vapidDetails: vapid,
      topic: createHash("sha256").update(job.notification_id).digest("base64url").slice(0, 32) },
  );
  try {
    const addresses = await resolver.resolve4(endpoint.hostname);
    if (!addresses.length || addresses.some((address) => blocked.check(address, "ipv4"))) {
      return { result: "failed", error: "blocked_address" };
    }
    const { status, retryAfter } = await send(addresses[0], endpoint, details);
    if (status >= 200 && status < 300) return { result: "sent", error: null };
    const error = status >= 100 && status < 600 ? `http_${status}` : "network";
    if (status === 404 || status === 410) return { result: "gone", error };
    if (status === 0 || status === 408 || status === 425 || status === 429 || status >= 500) {
      return { result: "retry", error, retrySeconds: retrySeconds(retryAfter) };
    }
    return { result: "failed", error };
  } catch {
    return { result: "retry", error: "network" };
  }
}

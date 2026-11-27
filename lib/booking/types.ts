export const consentVersion = "r5-privacy-v1";

export type PublicService = {
  id: string;
  name: string;
  description: string;
  revision: number;
  duration: number;
  buffer: number;
  price: number;
  deposit: number;
};

export type Catalog = {
  name: string;
  today: string;
  lastDay: string;
  policyRevision: number;
  cancellationPolicy: string;
  depositPolicy: string;
  reportMinutes: number;
  cancellationMinutes: number;
  services: PublicService[];
};

export type BookingRequest = {
  slug: string;
  service: string;
  start: string;
  revision: number;
  policy: number;
  name: string;
  phone: string;
  consent: string;
  key: string;
};

export type Confirmation = {
  shopName: string;
  serviceName: string;
  startsAt: string;
  endsAt: string;
  status: "pending_deposit" | "confirmed" | "completed" | "no_show" | "cancelled" | "expired";
  depositStatus: "not_required" | "awaiting_transfer" | "reported" | "verified";
  followup: "none" | "review_needed" | "resolved_recorded";
  price: number;
  deposit: number;
  dueAt: string | null;
  cancellationPolicy: string;
  depositPolicy: string;
  phoneLast4: string;
  canReport?: boolean;
  account: { bank: string; number: string; holder: string } | null;
};

export function validSlug(value: unknown): value is string {
  return typeof value === "string" && value.length <= 60 && /^[a-z0-9]+(-[a-z0-9]+)*$/.test(value);
}

export function validToken(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

const clock = new Intl.DateTimeFormat("ko-KR", { timeZone: "Asia/Seoul", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
const fullDate = new Intl.DateTimeFormat("ko-KR", { timeZone: "Asia/Seoul", dateStyle: "long", timeStyle: "short" });

export function seoulClock(value: string) {
  return clock.format(new Date(value));
}

export function seoulDateTime(value: string) {
  return fullDate.format(new Date(value));
}

export function won(value: number) {
  return `${value.toLocaleString("ko-KR")}원`;
}

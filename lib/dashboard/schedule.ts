export const statusLabels = {
  confirmed: "확정",
  pending_deposit: "예약금 대기",
  completed: "완료",
  no_show: "노쇼",
  cancelled: "취소",
  expired: "만료",
} as const;

export type BookingStatus = keyof typeof statusLabels;

export type BookingItem = {
  id: string;
  starts_at: string;
  ends_at: string;
  occupied_until: string;
  service_name: string;
  customer_name: string;
  status: BookingStatus;
};

export type BlockItem = { id: string; starts_at: string; ends_at: string; reason: string };
export type Schedule = {
  bookings: BookingItem[];
  blocks: BlockItem[];
  summary: Partial<Record<BookingStatus, number>>;
};

export type BookingDetail = Omit<BookingItem, "occupied_until"> & {
  revision: number;
  source: "online" | "manual";
  customer_phone: string;
  deposit_status: "not_required" | "awaiting_transfer" | "reported" | "verified";
  money_followup_status: "none" | "review_needed" | "resolved_recorded";
  price_krw: number;
  deposit_krw: number;
  deposit_due_at: string | null;
  duration_minutes: number;
  buffer_minutes: number;
  cancellation_policy: string;
  deposit_policy: string;
  events: { id: string; type: string; at: string; reason: string | null; from: string | null; to: string | null; channel: string | null }[];
};

export function validDay(value: unknown): value is string {
  if (typeof value !== "string" || !/^20\d{2}-\d{2}-\d{2}$/.test(value)) return false;
  const time = Date.parse(value);
  return Number.isFinite(time) && new Date(time).toISOString().slice(0, 10) === value;
}

const localDay = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit" });
const dateHeading = new Intl.DateTimeFormat("ko-KR", { timeZone: "UTC", month: "long", day: "numeric", weekday: "short" });

export function seoulDay(time = new Date()) {
  return localDay.format(time);
}
export function dayHeading(day: string) {
  return dateHeading.format(new Date(day));
}
export function addDays(day: string, n: number) {
  return new Date(Date.parse(day) + n * 86_400_000).toISOString().slice(0, 10);
}

export function weekday(day: string) {
  return (new Date(day).getUTCDay() + 6) % 7;
}

function addMonths(day: string, n: number) {
  const date = new Date(day);
  date.setUTCMonth(date.getUTCMonth() + n, 1);
  return date.toISOString().slice(0, 10);
}

export function getRange(day: string, view: "day" | "week" | "month") {
  if (view === "month") {
    const from = `${day.slice(0, 7)}-01`;
    return { from, until: addMonths(from, 1), previous: addMonths(from, -1), next: addMonths(from, 1) };
  }
  const length = view === "week" ? 7 : 1;
  const from = view === "week" ? addDays(day, -weekday(day)) : day;
  const until = addDays(from, length);
  return { from, until, previous: addDays(from, -length), next: until };
}

export function overlapsDay(start: string, end: string, day: string) {
  return Date.parse(start) < Date.parse(`${addDays(day, 1)}T00:00:00+09:00`)
    && Date.parse(end) > Date.parse(`${day}T00:00:00+09:00`);
}

export function startsInSeoul(value: string) {
  const [day, time, extra] = value.split("T");
  if (extra !== undefined || !validDay(day) || !/^(?:[01]\d|2[0-3]):(?:00|15|30|45)$/.test(time ?? "")) return null;
  return `${day}T${time}:00+09:00`;
}

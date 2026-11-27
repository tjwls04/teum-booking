import { isUuid } from "../dashboard/settings";

export const notificationLabels = {
  created: "신규 예약",
  deposit_reported: "고객 입금 신고",
  expired: "예약 만료",
  deposit_reported_late: "늦은 입금 신고",
  deposit_delayed: "입금 확인 지연",
  today: "당일 예약 안내",
} as const;

export type NotificationKind = keyof typeof notificationLabels;
export type InboxItem = {
  id: string;
  booking_id: string;
  kind: NotificationKind;
  created_at: string;
  read_at: string | null;
};
export type PushPreferences = {
  enabled: boolean;
  devices: { id: string; created_at: string }[];
};

export function notificationTarget(item: Pick<InboxItem, "booking_id" | "kind">) {
  return item.kind.startsWith("deposit_")
    ? `/dashboard/deposits/${item.booking_id}`
    : `/dashboard/schedule/${item.booking_id}`;
}

export function notificationPath(id: unknown) {
  return typeof id === "string" && id.length === 36 && isUuid(id) ? `/dashboard/notifications/open/${id}` : null;
}

import type { BookingStatus } from "./schedule";

export const depositLabels = {
  not_required: "없음",
  awaiting_transfer: "입금 대기",
  reported: "이체 신고됨",
  verified: "확인됨",
} as const;

export const depositTabs = {
  waiting: "입금 대기",
  reported: "이체 신고",
  verified: "입금 확인 완료",
  review: "금전 후속 확인",
  resolved: "후속 처리 기록",
} as const;

export const moneyEventLabels: Record<string, string> = {
  deposit_verified: "사업자 입금 확인 · 예약 확정",
  deposit_verified_after_close: "종료 건 수납 확인",
  deposit_discrepancy: "입금액 차이 기록",
  manual_refund_recorded: "수동 환불 기록",
  no_refund_recorded: "환불 없이 처리한 기록",
  deposit_reported: "고객 이체 신고",
  deposit_reported_late: "기한 이후 고객 이체 신고",
  expired: "예약 만료",
  cancelled: "예약 취소",
};

export type DepositTab = keyof typeof depositTabs;

export type DepositItem = {
  id: string;
  customer_name: string;
  service_name: string;
  starts_at: string;
  deposit_due_at: string | null;
  deposit_krw: number;
  status: BookingStatus;
  deposit_status: keyof typeof depositLabels;
};

export type DepositList = {
  counts: Partial<Record<DepositTab, number>>;
  items: DepositItem[];
};

export type DepositDetail = DepositItem & {
  revision: number;
  money_followup_status: "none" | "review_needed" | "resolved_recorded";
  refundable_krw: number;
  events: { id: string; type: string; at: string; amount_krw: number | null; reason: string | null }[];
};

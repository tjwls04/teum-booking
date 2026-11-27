import { randomUUID } from "node:crypto";
import Link from "next/link";
import { notFound } from "next/navigation";
import { seoulDateTime, won } from "../../../../lib/booking/types";
import { type DepositDetail, depositLabels, moneyEventLabels } from "../../../../lib/dashboard/deposits";
import { statusLabels } from "../../../../lib/dashboard/schedule";
import { requireShop } from "../../../../lib/dashboard/server";
import { isUuid } from "../../../../lib/dashboard/settings";
import styles from "../../schedule/schedule.module.css";
import { Heading, ReadError } from "../../section";
import { Field, ServiceRequestId, SettingsForm } from "../../settings-form";
import { recordDeposit } from "../actions";

const operations = {
  confirm: "입금 확인",
  receipt: "종료 건 수납 기록",
  refund: "수동 환불 기록",
  no_refund: "환불 없이 처리 기록",
} as const;

function DepositOperation({ shop, booking, operation }: {
  shop: string; booking: DepositDetail; operation: keyof typeof operations;
}) {
  const label = operations[operation];
  const isReceipt = operation === "confirm" || operation === "receipt";
  const acknowledgment = isReceipt ? "은행 입금 내역을 직접 확인했습니다."
    : operation === "refund" ? "앱 밖에서 환불을 완료했고, 실제 처리 금액을 확인했습니다."
      : "이 건을 환불 없이 정리한 결과를 확인했습니다.";
  return (
    <details className="border-t border-rule py-2">
      <summary className="text-link cursor-pointer">{label}</summary>
      <SettingsForm action={recordDeposit} submitLabel={`${label} 저장`}>
        <ServiceRequestId initial={randomUUID()} />
        <input type="hidden" name="shop" value={shop} />
        <input type="hidden" name="booking" value={booking.id} />
        <input type="hidden" name="revision" value={booking.revision} />
        <input type="hidden" name="operation" value={operation} />
        {operation !== "no_refund" && (
          <Field name="amount" type="number" label={isReceipt ? "실제 입금액 (원)" : "실제 환불 금액 (원)"}
            initial={operation === "confirm" ? booking.deposit_krw : ""}
            min={1} max={operation === "refund" ? booking.refundable_krw : 2_147_483_647} step={1} required />
        )}
        <Field name="reason" label="처리 사유" maxLength={200} required={operation !== "confirm"}
          hint={operation === "confirm" ? "확인한 입금 합계를 입력하세요. 예약금과 금액이 다르면 사유와 함께 차이만 기록되고 예약은 확정 대기 상태로 유지돼요." : "은행 계좌번호나 고객 연락처는 적지 마세요."} />
        <label className="flex min-h-11 items-start gap-2 py-2">
          <input type="checkbox" name="checked" value="yes" className="mt-1 accent-pine" required />
          <span>{acknowledgment}</span>
        </label>
      </SettingsForm>
    </details>
  );
}

export default async function DepositDetails({ params, searchParams }: PageProps<"/dashboard/deposits/[bookingId]">) {
  const { supabase, shop } = await requireShop();
  const { bookingId } = await params;
  if (!isUuid(bookingId)) notFound();
  const { data, error } = await supabase.rpc("r7_deposit_detail", { p_shop: shop.id, p_booking: bookingId });
  if (error) return <ReadError />;
  const booking = data as DepositDetail | null;
  if (!booking) notFound();

  const { saved } = await searchParams;
  const pending = booking.status === "pending_deposit";
  const closed = booking.status === "cancelled" || booking.status === "expired";
  const review = booking.money_followup_status === "review_needed";
  const delayed = pending && booking.deposit_status === "reported" && booking.deposit_due_at
    && Date.parse(booking.deposit_due_at) <= Date.now();
  const changedAmount = pending && booking.events.some((item) => item.type === "deposit_discrepancy");
  const actions: (keyof typeof operations)[] = [];
  if (pending) actions.push("confirm");
  if (closed && booking.deposit_status !== "verified") actions.push("receipt");
  if (closed && review) {
    if (booking.refundable_krw > 0) actions.push("refund");
    actions.push("no_refund");
  }

  return (
    <>
      <div className={styles.toolbar}>
        <Link prefetch={false} href="/dashboard/deposits" className="text-link">예약금 목록</Link>
        <Link prefetch={false} href={`/dashboard/schedule/${booking.id}`} className="text-link">예약 상세</Link>
      </div>
      <Heading title="예약금 상세" description="실제 송금과 환불은 은행에서 진행하고, 이 화면에는 처리 결과만 기록하세요." saved={saved === "1"} />
      <dl className={styles.detail}>
        <div><dt>고객</dt><dd>{booking.customer_name}</dd></div>
        <div><dt>시술</dt><dd>{booking.service_name}</dd></div>
        <div><dt>방문</dt><dd>{seoulDateTime(booking.starts_at)}</dd></div>
        <div><dt>예약 상태</dt><dd>{statusLabels[booking.status]}</dd></div>
        <div><dt>입금 상태</dt><dd>{depositLabels[booking.deposit_status]}</dd></div>
        <div><dt>예약금</dt><dd>{won(booking.deposit_krw)}</dd></div>
        {booking.deposit_due_at && <div><dt>신고 기한</dt><dd>{seoulDateTime(booking.deposit_due_at)}</dd></div>}
        {review && <div><dt>금전 후속</dt><dd>확인 필요</dd></div>}
        {booking.money_followup_status === "resolved_recorded" && <div><dt>금전 후속</dt><dd>처리 기록됨</dd></div>}
        {closed && <div><dt>확인액 − 기록한 환불액</dt><dd>{won(booking.refundable_krw)}</dd></div>}
      </dl>
      {delayed && <p className="auth-notice mb-4">입금 확인이 지연되고 있어요. 신고된 방문 시간은 유지됩니다.</p>}
      {changedAmount && <p className="auth-notice mb-4">예약금과 다른 입금액이 기록됐어요. 실제 금액을 다시 확인해 주세요.</p>}
      {closed && <p className="mb-4 text-sm text-muted">금전 처리 기록을 추가해도 예약 상태와 방문 시간은 유지됩니다.</p>}
      {closed && review && booking.refundable_krw > 0 && (
        <p className="auth-notice mb-4">환불 기록은 한 번 저장하면 금전 처리가 종료돼요. 나눠 환불했다면 모두 처리한 뒤 합계를 한 번에 기록해 주세요.</p>
      )}
      {actions.map((operation) => <DepositOperation key={`${operation}:${booking.revision}`} shop={shop.id} booking={booking} operation={operation} />)}

      <h2 className="mt-6 mb-2 font-bold text-pine">금전 처리 이력</h2>
      {booking.events.length === 0 ? <p className="text-muted">아직 처리 기록이 없어요.</p> : (
        <ul className={styles.rows}>
          {booking.events.map((event) => (
            <li className={styles.row} key={event.id}>
              <div className="min-w-0">
                <p className="font-semibold">{moneyEventLabels[event.type] ?? "금전 기록"}</p>
                {event.amount_krw != null && <p className="text-sm">{won(event.amount_krw)}</p>}
                {event.reason && <p className="text-sm text-muted">{event.reason}</p>}
              </div>
              <span className="text-sm text-muted">{seoulDateTime(event.at)}</span>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}

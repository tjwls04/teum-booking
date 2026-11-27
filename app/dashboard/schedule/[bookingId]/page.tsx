import { randomUUID } from "node:crypto";
import Link from "next/link";
import { notFound } from "next/navigation";
import type { ReactNode } from "react";
import { seoulClock, seoulDateTime, won } from "../../../../lib/booking/types";
import { depositLabels, moneyEventLabels } from "../../../../lib/dashboard/deposits";
import { type BookingDetail, seoulDay, statusLabels } from "../../../../lib/dashboard/schedule";
import { requireShop } from "../../../../lib/dashboard/server";
import { isUuid } from "../../../../lib/dashboard/settings";
import { Heading, ReadError } from "../../section";
import { Field, ServiceRequestId, SettingsForm } from "../../settings-form";
import { changeBooking } from "../actions";
import styles from "../schedule.module.css";

const eventLabels: Record<string, string> = {
  created: "예약 생성", rescheduled: "시간 변경", cancelled: "취소", expired: "만료",
  completed: "시술 완료", no_show: "노쇼", deposit_reported: "이체 신고", deposit_reported_late: "기한 이후 이체 신고",
};

function Operation({ shop, booking, name, label, children }: {
  shop: string; booking: BookingDetail; name: string; label: string; children?: ReactNode;
}) {
  return (
    <details className="border-t border-rule py-2">
      <summary className="text-link cursor-pointer">{label}</summary>
      <SettingsForm action={changeBooking} submitLabel={label}>
        <ServiceRequestId initial={randomUUID()} />
        <input type="hidden" name="shop" value={shop} />
        <input type="hidden" name="booking" value={booking.id} />
        <input type="hidden" name="revision" value={booking.revision} />
        <input type="hidden" name="operation" value={name} />
        {children}
      </SettingsForm>
    </details>
  );
}

export default async function DetailPage({ params, searchParams }: PageProps<"/dashboard/schedule/[bookingId]">) {
  const { supabase, shop } = await requireShop();
  const { bookingId } = await params;
  if (!isUuid(bookingId)) notFound();
  const { data, error } = await supabase.rpc("r6_detail", { p_shop: shop.id, p_booking: bookingId });
  if (error) return <ReadError />;
  const booking = data as BookingDetail | null;
  if (!booking) notFound();
  const { saved } = await searchParams;
  const active = booking.status === "confirmed" || booking.status === "pending_deposit";
  const started = Date.parse(booking.starts_at) <= Date.now();
  const day = seoulDay(new Date(booking.starts_at));
  const fields = [
    ["상태", statusLabels[booking.status]],
    ["고객", booking.customer_name],
    ["휴대전화 번호", booking.customer_phone],
    ["시술", booking.service_name],
    ["예약 시간", `${seoulDateTime(booking.starts_at)} ~ ${seoulDateTime(booking.ends_at)}`],
    ["시술·준비", `${booking.duration_minutes}분 · ${booking.buffer_minutes}분`],
    ["예약 방식", booking.source === "online" ? "온라인" : "수동"],
    ["총 금액", won(booking.price_krw)],
    ["예약금", `${won(booking.deposit_krw)} · ${depositLabels[booking.deposit_status]}`],
  ];
  if (booking.deposit_due_at) fields.push(["예약금 기한", seoulDateTime(booking.deposit_due_at)]);
  if (booking.money_followup_status === "review_needed") fields.push(["금전 후속 상태", "확인 필요"]);
  if (booking.money_followup_status === "resolved_recorded") fields.push(["금전 후속 상태", "처리 기록됨"]);

  return (
    <>
      <Link href={`/dashboard/schedule?date=${day}`} className="text-link mb-3">일정으로 돌아가기</Link>
      <Heading title="예약 상세" saved={saved === "1"} />
      {booking.deposit_krw > 0 && <Link prefetch={false} className="text-link mb-3" href={`/dashboard/deposits/${booking.id}`}>예약금 관리</Link>}
      <dl className={styles.detail}>
        {fields.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}
      </dl>
      {(booking.cancellation_policy || booking.deposit_policy) && (
        <details className="border-t border-rule py-2">
          <summary className="text-link cursor-pointer">예약 당시 안내</summary>
          <p className="text-sm whitespace-pre-wrap">{booking.cancellation_policy}</p>
          <p className="text-sm whitespace-pre-wrap">{booking.deposit_policy}</p>
        </details>
      )}
      {active && !started && (
        <Operation key={`move:${booking.revision}`} shop={shop.id} booking={booking} name="move" label="시간 변경">
          <Field label="새 시작 (서울 시간)" name="start" type="datetime-local" step={900}
            initial={`${day}T${seoulClock(booking.starts_at)}`} required />
        </Operation>
      )}
      {active && (
        <Operation key={`cancel:${booking.revision}`} shop={shop.id} booking={booking} name="cancel" label="예약 취소">
          <Field label="취소 사유" name="reason" maxLength={200} required />
          {booking.deposit_krw > 0 && <p className="text-sm text-muted">예약을 취소하면 금전 후속 확인이 필요한 건으로 기록돼요.</p>}
        </Operation>
      )}
      {started && booking.status === "confirmed" && (
        <>
          <Operation shop={shop.id} booking={booking} name="complete" label="시술 완료로 기록" />
          <Operation shop={shop.id} booking={booking} name="no_show" label="노쇼로 기록" />
        </>
      )}
      <h2 className="mt-6 mb-2 font-bold text-pine">변경 이력</h2>
      {booking.events.length === 0 ? <p className="text-muted">기록된 변경이 없어요.</p> : (
        <ul className={styles.rows}>
          {booking.events.map((event) => (
            <li className={styles.row} key={event.id}>
              <div className="min-w-0">
                <p className="font-semibold">{eventLabels[event.type] ?? moneyEventLabels[event.type] ?? "예약 이력"}</p>
                {event.channel && <p className="text-sm text-muted">{event.channel === "kakao" ? "카카오톡" : "전화"}</p>}
                {event.from && event.to && <p className="text-sm text-muted">{seoulDateTime(event.from)} → {seoulDateTime(event.to)}</p>}
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

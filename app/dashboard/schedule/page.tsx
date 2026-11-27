import Link from "next/link";
import { seoulDateTime } from "../../../lib/booking/types";
import {
  addDays, type BlockItem, type BookingItem, type BookingStatus, dayHeading,
  getRange, overlapsDay, type Schedule, seoulDay, statusLabels, validDay, weekday,
} from "../../../lib/dashboard/schedule";
import { requireShop } from "../../../lib/dashboard/server";
import { Heading, ReadError } from "../section";
import { SettingsForm } from "../settings-form";
import { releaseBlock } from "./actions";
import styles from "./schedule.module.css";
import { Counts } from "./summary";

type View = "day" | "week" | "month";
const viewLabels = { day: "일간", week: "주간", month: "월간" } as const;
const weekdays = ["월", "화", "수", "목", "금", "토", "일"] as const;

function scheduleHref(date: string, view: View, status: string) {
  const params = new URLSearchParams({ date, view });
  if (status) params.set("status", status);
  return `/dashboard/schedule?${params}`;
}

function ScheduleRows({ bookings, blocks, shopId, day }: {
  bookings: BookingItem[]; blocks: BlockItem[]; shopId: string; day: string;
}) {
  const rows = [
    ...bookings.map((value) => ({ kind: "booking" as const, value })),
    ...blocks.map((value) => ({ kind: "block" as const, value })),
  ].sort((a, b) => Date.parse(a.value.starts_at) - Date.parse(b.value.starts_at));
  if (!rows.length) return <p className="text-sm text-muted">일정이 없어요.</p>;

  return (
    <ul className={styles.rows}>
      {rows.map(({ kind, value }) => (
        <li className={styles.row} key={`${kind}:${value.id}`}>
          {kind === "booking" ? (
            <div className="min-w-0">
              <Link prefetch={false} className="text-link" href={`/dashboard/schedule/${value.id}`}>{value.customer_name} · {value.service_name}</Link>
              <p className="text-sm text-muted">{seoulDateTime(value.starts_at)} · {statusLabels[value.status]}</p>
            </div>
          ) : (
            <>
              <div className="min-w-0 py-2">
                <p className="font-semibold text-pine">시간 차단 · {value.reason}</p>
                <p className="text-sm text-muted">{seoulDateTime(value.starts_at)} ~ {seoulDateTime(value.ends_at)}</p>
              </div>
              <SettingsForm action={releaseBlock} submitLabel="차단 해제">
                <input type="hidden" name="shop" value={shopId} />
                <input type="hidden" name="block" value={value.id} />
                <input type="hidden" name="date" value={day} />
              </SettingsForm>
            </>
          )}
        </li>
      ))}
    </ul>
  );
}

export default async function SchedulePage({ searchParams }: PageProps<"/dashboard/schedule">) {
  const { supabase, shop } = await requireShop();
  const params = await searchParams;
  const view: View = params.view === "week" || params.view === "month" ? params.view : "day";
  const day = validDay(params.date) ? params.date : seoulDay();
  const status = typeof params.status === "string" && Object.hasOwn(statusLabels, params.status) ? params.status as BookingStatus : "";
  const { from, until, previous, next } = getRange(day, view);
  const { data, error } = await supabase.rpc("r6_schedule", {
    p_shop: shop.id, p_from: from < "2000-01-01" ? "2000-01-01" : from,
    p_until: until > "2100-01-01" ? "2100-01-01" : until, p_status: status || null,
  });
  const schedule = data as Schedule | null;
  const days: string[] = [];
  for (let date = from; date < until; date = addDays(date, 1)) days.push(date);
  const bookings = schedule?.bookings.slice(0, 500) ?? [];
  const blocks = schedule?.blocks.slice(0, 500) ?? [];
  const daysWithItems = days.map((date) => ({
    date,
    bookings: bookings.filter((b) => overlapsDay(b.starts_at, b.occupied_until, date)),
    blocks: blocks.filter((b) => overlapsDay(b.starts_at, b.ends_at, date)),
  }));

  return (
    <>
      <Heading title="예약 관리" description="서울 기준으로 예약과 차단 일정을 확인하세요." saved={params.saved === "1"} />
      <div className={styles.toolbar}>
        <Link prefetch={false} href={`/dashboard/schedule/new?date=${day}`} className="status-link text-pine">수동 예약 등록</Link>
        <Link prefetch={false} href={`/dashboard/schedule/block?date=${day}`} className="text-link">시간 차단</Link>
      </div>
      <nav className={styles.toolbar} aria-label="캘린더 보기">
        {(Object.entries(viewLabels) as [View, string][]).map(([mode, text]) => (
          <Link prefetch={false} key={mode} className="text-link" href={scheduleHref(day, mode, status)}
            aria-current={view === mode ? "page" : undefined}>{text}</Link>
        ))}
      </nav>
      <form action="/dashboard/schedule" method="get" className={styles.filters}>
        <input type="hidden" name="view" value={view} />
        <label className="grid gap-1">
          기준 날짜
          <input type="date" name="date" className="auth-input" min="2000-01-01" max="2099-12-31" defaultValue={day} required />
        </label>
        <label className="grid gap-1">
          예약 상태
          <select name="status" className="auth-input" defaultValue={status}>
            <option value="">전체</option>
            {Object.entries(statusLabels).map(([key, text]) => <option key={key} value={key}>{text}</option>)}
          </select>
        </label>
        <button type="submit" className="auth-button">조회</button>
      </form>
      <nav className={styles.toolbar} aria-label="기간 이동">
        {validDay(previous) && <Link prefetch={false} href={scheduleHref(previous, view, status)} className="text-link">이전</Link>}
        <Link prefetch={false} href={scheduleHref(seoulDay(), view, status)} className="text-link">오늘</Link>
        {validDay(next) && <Link prefetch={false} href={scheduleHref(next, view, status)} className="text-link">다음</Link>}
      </nav>
      <p className="font-semibold text-pine">
        {view === "month" ? `${from.slice(0, 4)}년 ${Number(from.slice(5, 7))}월`
          : view === "week" ? `${dayHeading(from)} ~ ${dayHeading(addDays(until, -1))}` : dayHeading(day)}
      </p>
      {error || !schedule ? <ReadError /> : (
        <>
          <Counts summary={schedule.summary} />
          {(schedule.bookings.length > 500 || schedule.blocks.length > 500) &&
            <p className="auth-notice mb-3" role="status">표시 한도를 넘었어요. 더 좁은 기간을 선택해 주세요.</p>}
          {view !== "day" && (
            <nav className={styles.month} aria-label={view === "month" ? "월간 캘린더" : "주간 캘린더"}>
              {weekdays.map((name) => <div key={name} className={styles.day}>{name}</div>)}
              {weekdays.slice(0, weekday(from)).map((name) => <div key={`blank-${name}`} className={styles.day} aria-hidden="true" />)}
              {daysWithItems.map((entry) => (
                <div key={entry.date} className={styles.day} data-selected={entry.date === day}>
                  {validDay(entry.date) && (
                    <Link prefetch={false} className="text-link w-full justify-center" href={scheduleHref(entry.date, "day", status)}
                      aria-label={`${dayHeading(entry.date)} 예약 ${entry.bookings.length}건, 차단 ${entry.blocks.length}건`}>
                      {Number(entry.date.slice(-2))}
                    </Link>
                  )}
                  {entry.bookings.length > 0 && <span>{entry.bookings.length}건</span>}
                  {entry.blocks.length > 0 && <span>차단 {entry.blocks.length}</span>}
                </div>
              ))}
            </nav>
          )}
          {view === "month" ? (
            <>
              <h2 className="mt-6 mb-2 font-bold text-pine">예약·차단 목록</h2>
              <ScheduleRows bookings={bookings} blocks={blocks} shopId={shop.id} day={day} />
            </>
          ) : daysWithItems.map((entry) => (
            <section className="mt-4" key={entry.date} aria-label={dayHeading(entry.date)}>
              {view === "week" && (
                <h2 className="font-semibold">
                  <Link prefetch={false} href={scheduleHref(entry.date, "day", status)} className="text-link">{dayHeading(entry.date)}</Link>
                </h2>
              )}
              <ScheduleRows bookings={entry.bookings} blocks={entry.blocks} shopId={shop.id} day={entry.date} />
            </section>
          ))}
        </>
      )}
    </>
  );
}

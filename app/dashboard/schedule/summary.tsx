import Link from "next/link";
import { seoulClock } from "../../../lib/booking/types";
import { addDays, type BookingStatus, type Schedule, seoulDay, statusLabels } from "../../../lib/dashboard/schedule";
import type { requireShop } from "../../../lib/dashboard/server";
import styles from "./schedule.module.css";

export function Counts({ summary }: { summary: Schedule["summary"] }) {
  return (
    <dl className={styles.counts}>
      {(Object.entries(statusLabels) as [BookingStatus, string][]).map(([status, text]) => (
        <div key={status}><dt>{text}</dt><dd className="font-semibold">{summary[status] ?? 0}</dd></div>
      ))}
    </dl>
  );
}

export async function Today({ supabase, shop }: Awaited<ReturnType<typeof requireShop>>) {
  const today = seoulDay();
  const { data, error } = await supabase.rpc("r6_schedule", {
    p_shop: shop.id, p_from: today, p_until: addDays(today, 1), p_status: null,
  });
  const schedule = data as Schedule | null;
  return (
    <section className="mb-8 border-b border-rule pb-4" aria-labelledby="today-title">
      <h2 className="font-bold text-pine" id="today-title">오늘의 예약과 상태</h2>
      {error || !schedule ? <p className="auth-error mt-2">오늘 일정을 불러오지 못했어요.</p> : (
        <>
          <Counts summary={schedule.summary} />
          {schedule.bookings.length ? (
            <ul className={styles.rows}>
              {schedule.bookings.slice(0, 5).map((item) => (
                <li key={item.id} className={styles.row}>
                  <Link prefetch={false} className="text-link" href={`/dashboard/schedule/${item.id}`}>
                    {seoulClock(item.starts_at)} {item.customer_name} · {item.service_name}
                  </Link>
                  <span className="text-sm text-muted">{statusLabels[item.status]}</span>
                </li>
              ))}
            </ul>
          ) : <p className="text-sm text-muted">오늘 예약이 없어요.</p>}
        </>
      )}
      <Link prefetch={false} href="/dashboard/schedule" className="text-link mt-2">전체 일정 보기</Link>
    </section>
  );
}

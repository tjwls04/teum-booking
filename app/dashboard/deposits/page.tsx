import Link from "next/link";
import { seoulDateTime, won } from "../../../lib/booking/types";
import { depositLabels, type DepositList, type DepositTab, depositTabs } from "../../../lib/dashboard/deposits";
import { statusLabels } from "../../../lib/dashboard/schedule";
import { requireShop } from "../../../lib/dashboard/server";
import styles from "../schedule/schedule.module.css";
import { Heading, ReadError } from "../section";

export default async function DepositPage({ searchParams }: PageProps<"/dashboard/deposits">) {
  const { supabase, shop } = await requireShop();
  const params = await searchParams;
  const tab = typeof params.tab === "string" && Object.hasOwn(depositTabs, params.tab) ? params.tab as DepositTab : "waiting";
  const page = typeof params.page === "string" && /^[1-9]\d{0,3}$/.test(params.page)
    ? Math.min(Number(params.page), 1000) : 1;
  const { data, error } = await supabase.rpc("r7_deposits", { p_shop: shop.id, p_tab: tab, p_page: page });
  const model = data as DepositList | null;

  return (
    <>
      <Heading title="예약금 관리" description="은행에서 직접 확인한 입금과 수동 처리 결과를 기록하세요." />
      {error || !model ? <ReadError /> : (
        <>
          <nav className={styles.toolbar} aria-label="예약금 분류">
            {(Object.entries(depositTabs) as [DepositTab, string][]).map(([key, label]) => (
              <Link prefetch={false} key={key} className="text-link" href={`/dashboard/deposits?tab=${key}`}
                aria-current={key === tab ? "page" : undefined}>
                {label} {model.counts[key] ?? 0}
              </Link>
            ))}
          </nav>
          {!model.items.length ? <p className="text-muted">이 분류에 해당하는 예약이 없어요.</p> : (
            <ul className={styles.rows}>
              {model.items.slice(0, 40).map((item) => (
                <li key={item.id} className={styles.row}>
                  <div className="min-w-0 pb-2">
                    <Link prefetch={false} className="text-link" href={`/dashboard/deposits/${item.id}`}>
                      {item.customer_name} · {item.service_name}
                    </Link>
                    <p className="text-sm text-muted">{seoulDateTime(item.starts_at)} · {statusLabels[item.status]} · {depositLabels[item.deposit_status]}</p>
                    {item.status === "pending_deposit" && item.deposit_status === "reported" && item.deposit_due_at &&
                      Date.parse(item.deposit_due_at) <= Date.now() && (
                      <p className="text-sm font-semibold text-pine">입금 확인 지연</p>
                    )}
                    {item.status === "pending_deposit" && item.deposit_due_at && (
                      <p className="text-sm text-muted">신고 기한 {seoulDateTime(item.deposit_due_at)}</p>
                    )}
                  </div>
                  <p className="py-1 font-semibold">{won(item.deposit_krw)}</p>
                </li>
              ))}
            </ul>
          )}
          {(page > 1 || model.items.length > 40) && (
            <nav className={styles.toolbar} aria-label="예약금 목록 페이지">
              {page > 1 && <Link prefetch={false} className="text-link" href={`?tab=${tab}&page=${page - 1}`}>이전</Link>}
              <span>{page}페이지</span>
              {model.items.length > 40 && page < 1000 &&
                <Link prefetch={false} className="text-link" href={`?tab=${tab}&page=${page + 1}`}>다음</Link>}
            </nav>
          )}
        </>
      )}
    </>
  );
}

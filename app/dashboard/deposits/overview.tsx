import Link from "next/link";
import type { DepositList } from "../../../lib/dashboard/deposits";
import type { requireShop } from "../../../lib/dashboard/server";

export async function DepositOverview({ supabase, shop }: Awaited<ReturnType<typeof requireShop>>) {
  const { data, error } = await supabase.rpc("r7_deposits", { p_shop: shop.id, p_tab: null, p_page: 1 });
  const counts = (data as DepositList | null)?.counts;
  return (
    <section className="mb-8 border-b border-rule pb-4">
      <h2 className="font-bold text-pine">예약금 상태</h2>
      {error || !counts ? <p className="auth-error">예약금 상태를 불러오지 못했어요.</p> : (
        <p className="mt-2 text-sm text-muted">
          입금 대기 {counts.waiting ?? 0}건 · 이체 신고 {counts.reported ?? 0}건 · 입금 확인 완료 {counts.verified ?? 0}건 · 금전 후속 확인 {counts.review ?? 0}건
        </p>
      )}
      <Link prefetch={false} href="/dashboard/deposits" className="text-link mt-2">예약금 관리 열기</Link>
    </section>
  );
}

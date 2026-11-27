import { requireShop } from "../../../lib/dashboard/server";
import type { Period } from "../../../lib/dashboard/settings";
import { Heading, ReadError } from "../section";
import { HoursEditor } from "./editor";

export default async function HoursPage({ searchParams }: PageProps<"/dashboard/hours">) {
  const { supabase, shop } = await requireShop();
  const [{ data, error }, { saved }] = await Promise.all([
    supabase.from("shop_weekly_periods").select("iso_weekday, period_kind, start_minute, end_minute")
      .eq("shop_id", shop.id).order("iso_weekday").order("period_kind", { ascending: false })
      .order("start_minute").returns<Period[]>(),
    searchParams,
  ]);

  return (
    <>
      <Heading title="영업시간"
        description="서울 현지 시각을 15분 단위로 입력하세요. 자정에 끝나는 구간은 24:00을 사용하고, 다음 날 이어지는 시간은 해당 요일에 따로 등록하세요."
        saved={saved === "1"} />
      {error ? <ReadError /> : (
        <HoursEditor key={shop.policy_revision} shopId={shop.id} revision={shop.policy_revision} periods={data ?? []} />
      )}
    </>
  );
}

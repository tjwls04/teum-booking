import Link from "next/link";
import { dashboardContext } from "../../lib/dashboard/server";
import { saveShop } from "./actions";
import { DepositOverview } from "./deposits/overview";
import { Today } from "./schedule/summary";
import { Heading } from "./section";
import { Field, SettingsForm } from "./settings-form";

export default async function DashboardPage({ searchParams }: PageProps<"/dashboard">) {
  const { shop, supabase } = await dashboardContext();
  const { saved } = await searchParams;

  return (
    <>
      <Heading title={shop ? "샵 정보" : "샵 등록"}
        description={shop ? "고객에게 표시될 샵 이름과 공개 주소를 수정할 수 있어요." : "샵을 등록하면 시술과 영업시간을 설정할 수 있어요."}
        saved={saved === "1"}
      />
      {shop && <Today shop={shop} supabase={supabase} />}
      {shop && <DepositOverview shop={shop} supabase={supabase} />}
      {shop && <Link href={`/book/${shop.slug}`} className="text-link mb-4">공개 예약 링크 열기</Link>}
      <SettingsForm key={shop?.policy_revision ?? 0} action={saveShop} submitLabel={shop ? "샵 정보 저장" : "샵 등록하기"}>
        <input type="hidden" name="shop" value={shop?.id ?? ""} />
        <input type="hidden" name="revision" value={shop?.policy_revision ?? ""} />
        <Field name="name" label="샵 이름" initial={shop?.name} maxLength={80} required />
        <Field name="slug" label="공개 주소" initial={shop?.slug} minLength={3} maxLength={60}
          autoCapitalize="none" autoCorrect="off" spellCheck={false} required
          hint="영문 소문자, 숫자, 하이픈으로 3~60자를 입력해 주세요."
        />
      </SettingsForm>
    </>
  );
}

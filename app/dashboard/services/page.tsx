import Link from "next/link";
import { requireShop, type Service, serviceColumns } from "../../../lib/dashboard/server";
import styles from "../dashboard.module.css";
import { Heading, ReadError } from "../section";

export default async function ServicesPage({ searchParams }: PageProps<"/dashboard/services">) {
  const { supabase, shop } = await requireShop();
  const [{ data, error }, { saved }] = await Promise.all([
    supabase.from("services").select(serviceColumns).eq("shop_id", shop.id).order("created_at").returns<Service[]>(),
    searchParams,
  ]);

  return (
    <>
      <Heading title="시술" description="가격과 시간을 정하고 공개 상태를 관리하세요." saved={saved === "1"} />
      <Link href="/dashboard/services/new" className="status-link mb-5 font-semibold text-pine">시술 등록</Link>
      {error && <ReadError />}
      {!error && !data?.length && <p className="text-muted">아직 등록한 시술이 없어요.</p>}
      {Boolean(data?.length) && (
        <ul>
          {data?.map((service) => (
            <li key={service.id} className={styles.service}>
              <div>
                <p className="font-semibold text-pine">{service.name}</p>
                <p className="text-sm text-muted">
                  {service.is_public ? "공개" : service.is_active ? "비공개" : "비활성"} · {service.duration_minutes}분
                  {" · "}{service.price_krw.toLocaleString("ko-KR")}원
                </p>
              </div>
              <Link href={`/dashboard/services/${service.id}`} className="text-link"
                aria-label={`${service.name} 수정`}>수정</Link>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}

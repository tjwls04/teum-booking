import { randomUUID } from "node:crypto";
import Link from "next/link";
import { notFound } from "next/navigation";
import { requireShop, type Service, serviceColumns } from "../../../../lib/dashboard/server";
import { isUuid } from "../../../../lib/dashboard/settings";
import { saveService } from "../../actions";
import styles from "../../dashboard.module.css";
import { Heading, ReadError } from "../../section";
import { Field, SelectField, ServiceRequestId, SettingsForm, TextField } from "../../settings-form";

export default async function ServicePage({ params }: PageProps<"/dashboard/services/[serviceId]">) {
  const { supabase, shop } = await requireShop();
  const { serviceId } = await params;
  let service: Service | null = null;

  if (serviceId !== "new") {
    if (!isUuid(serviceId)) notFound();
    const { data, error } = await supabase.from("services").select(serviceColumns)
      .eq("shop_id", shop.id).eq("id", serviceId).maybeSingle<Service>();
    if (error) return <ReadError />;
    if (!data) notFound();
    service = data;
  }

  return (
    <>
      <Link href="/dashboard/services" className="text-link mb-3">시술 목록</Link>
      <Heading title={service ? "시술 수정" : "시술 등록"}
        description="준비시간은 시술이 끝난 뒤 다음 고객을 받기까지 필요한 시간이에요." />
      <SettingsForm key={service ? `${service.id}:${service.revision}` : "new"}
        action={saveService} submitLabel="시술 저장">
        <input type="hidden" name="shop" value={shop.id} />
        <input type="hidden" name="service" value={service?.id ?? ""} />
        {!service && <ServiceRequestId initial={randomUUID()} />}
        <input type="hidden" name="revision" value={service?.revision ?? ""} />
        <Field label="시술 이름" name="name" initial={service?.name} maxLength={80} required />
        <TextField label="시술 설명" name="description" initial={service?.description ?? ""} maxLength={1000} />
        <div className={styles.fields}>
          <Field label="시술 시간 (분)" name="duration" type="number" min={15} max={1440} step={15}
            initial={service?.duration_minutes ?? 30} required />
          <Field label="준비시간 (분)" name="buffer" type="number" min={0} max={1440} step={15}
            initial={service?.buffer_minutes ?? 0} required />
          <Field label="가격 (원)" name="price" type="number" min={0} max={2147483647} step={1}
            initial={service?.price_krw} required />
          <Field label="예약금 (원)" name="deposit" type="number" min={0} max={2147483647} step={1}
            initial={service?.deposit_krw ?? 0} required hint="예약금을 받지 않으면 0원을 입력해 주세요." />
        </div>
        <SelectField label="공개 상태" name="state"
          initial={service?.is_public ? "public" : service?.is_active === false ? "inactive" : "private"}
          options={[["private", "비공개"], ["public", "공개"], ["inactive", "비활성"]]} />
      </SettingsForm>
    </>
  );
}

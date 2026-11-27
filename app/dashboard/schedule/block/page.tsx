import { randomUUID } from "node:crypto";
import Link from "next/link";
import { seoulDay, validDay } from "../../../../lib/dashboard/schedule";
import { requireShop } from "../../../../lib/dashboard/server";
import { Heading } from "../../section";
import { Field, ServiceRequestId, SettingsForm } from "../../settings-form";
import { createBlock } from "../actions";

export default async function BlockPage({ searchParams }: PageProps<"/dashboard/schedule/block">) {
  const { shop } = await requireShop();
  const params = await searchParams;
  const day = validDay(params.date) ? params.date : seoulDay();
  return (
    <>
      <Link href="/dashboard/schedule" className="text-link mb-3">일정으로 돌아가기</Link>
      <Heading title="시간 차단" description="개인 일정이나 임시 휴무로 예약을 받지 않을 시간을 지정하세요." />
      <SettingsForm action={createBlock} submitLabel="시간 차단 저장">
        <input type="hidden" name="shop" value={shop.id} />
        <ServiceRequestId initial={randomUUID()} />
        <Field label="시작 (서울 시간)" name="start" type="datetime-local" step={900} initial={`${day}T09:00`} required />
        <Field label="종료 (서울 시간)" name="end" type="datetime-local" step={900} initial={`${day}T10:00`} required />
        <Field label="차단 사유" name="reason" maxLength={120} placeholder="예: 개인 일정" required />
      </SettingsForm>
    </>
  );
}

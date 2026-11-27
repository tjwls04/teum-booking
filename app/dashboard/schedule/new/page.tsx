import { randomUUID } from "node:crypto";
import Link from "next/link";
import { won } from "../../../../lib/booking/types";
import { seoulDay, validDay } from "../../../../lib/dashboard/schedule";
import { requireShop } from "../../../../lib/dashboard/server";
import { Heading, ReadError } from "../../section";
import { Field, SelectField, ServiceRequestId, SettingsForm } from "../../settings-form";
import { manualBooking } from "../actions";

type Choice = { id: string; name: string; revision: number; price_krw: number; deposit_krw: number };

export default async function ManualPage({ searchParams }: PageProps<"/dashboard/schedule/new">) {
  const { supabase, shop } = await requireShop();
  const params = await searchParams;
  const day = validDay(params.date) ? params.date : seoulDay();
  const { data, error } = await supabase.from("services").select("id,name,revision,price_krw,deposit_krw")
    .eq("shop_id", shop.id).eq("is_active", true).order("created_at").returns<Choice[]>();
  const services = data ?? [];
  return (
    <>
      <Link href="/dashboard/schedule" className="text-link mb-3">일정으로 돌아가기</Link>
      <Heading title="수동 예약 등록" description="카카오톡이나 전화로 받은 예약을 등록하세요. 예약금이 있는 시술은 입금 대기로 저장돼요." />
      {error ? <ReadError /> : services.length === 0 ? (
        <p>등록 가능한 시술이 없어요. <Link href="/dashboard/services" className="text-link">시술 관리</Link></p>
      ) : (
        <SettingsForm action={manualBooking} submitLabel="예약 등록">
          <input type="hidden" name="shop" value={shop.id} />
          <input type="hidden" name="policy" value={shop.policy_revision} />
          <ServiceRequestId initial={randomUUID()} />
          <SelectField name="service" label="시술" initial={`${services[0].id}:${services[0].revision}`}
            options={services.map((item) => [`${item.id}:${item.revision}`, `${item.name} · ${won(item.price_krw)} (예약금 ${won(item.deposit_krw)})`])} />
          <Field label="예약 시작 (서울 시간)" name="start" type="datetime-local" step={900} initial={`${day}T09:00`} required />
          <Field label="고객 이름" name="name" maxLength={60} required />
          <Field label="휴대전화 번호" name="phone" type="tel" maxLength={20} autoComplete="off" required />
          <SelectField name="channel" label="예약 접수 경로" initial="kakao" options={[["kakao", "카카오톡"], ["phone", "전화"]]} />
        </SettingsForm>
      )}
    </>
  );
}

"use server";

import { revalidatePath } from "next/cache";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { startsInSeoul, validDay } from "../../../lib/dashboard/schedule";
import { requireBusiness } from "../../../lib/dashboard/server";
import { isUuid, type SettingsState } from "../../../lib/dashboard/settings";

const inputError = { error: "입력값을 확인해 주세요. 시간은 서울 기준 15분 단위예요." };
const errors: Record<string, string> = {
  r6_input: inputError.error,
  r6_time: "이미 점유된 시간이거나 영업시간·휴식·예약 가능 기간 조건을 충족하지 않아요.",
  r6_state: "현재 예약 상태나 시작 시각에서는 이 작업을 할 수 없어요.",
  r6_key: "이미 처리된 요청과 내용이 달라요. 화면을 다시 열어 결과를 확인해 주세요.",
  r6_stale: "예약 또는 설정이 변경됐어요. 새로고침한 뒤 다시 확인해 주세요.",
  r6_deadline: "기존 예약금 기한보다 앞선 시간으로 변경할 수 없어요.",
  r6_deposit: "이 시술은 예약금 안내와 계좌가 필요해요. 예약 정책을 확인해 주세요.",
  r6_missing: "이 일정을 변경할 권한이 없어요.",
  r4_owner: "이 샵의 일정을 변경할 권한이 없어요.",
};

function failure(error: { message: string; code: string }): SettingsState {
  if (error.code === "PGRST202") return { error: "예약 관리 기능이 아직 준비되지 않았어요." };
  return { error: Object.hasOwn(errors, error.message) ? errors[error.message] : "저장 결과를 확인하지 못했어요. 같은 화면에서 다시 시도해 주세요." };
}

async function sameOrigin() {
  const request = await headers();
  const origin = request.get("origin");
  return Boolean(origin && origin !== "null" && request.get("sec-fetch-site") !== "cross-site");
}

function field(form: FormData, key: string) {
  const input = form.get(key);
  return typeof input === "string" ? input.trim() : "";
}

function version(value: string) {
  const n = Number(value);
  return /^[0-9]{1,10}$/.test(value) && n >= 1 && n <= 2_147_483_647 ? n : null;
}

function redirectSaved(path: string): never {
  revalidatePath("/dashboard", "layout");
  redirect(path);
}

export async function manualBooking(_state: SettingsState, form: FormData): Promise<SettingsState> {
  if (!(await sameOrigin())) return inputError;
  const { supabase } = await requireBusiness(true);
  const shop = field(form, "shop");
  const key = field(form, "requestId");
  const [service, revision] = field(form, "service").split(":");
  const serviceRevision = version(revision ?? "");
  const policy = version(field(form, "policy"));
  const start = startsInSeoul(field(form, "start"));
  const name = field(form, "name");
  const phone = field(form, "phone").replace(/[ -]/g, "");
  const channel = field(form, "channel");
  if (!isUuid(shop) || !isUuid(key) || !isUuid(service) || !serviceRevision || !policy || !start
    || !name || name.length > 60 || /[\p{Cc}]/u.test(name) || !/^01[016789][0-9]{7,8}$/.test(phone)
    || !["kakao", "phone"].includes(channel)) return inputError;

  const { data, error } = await supabase.rpc("r6_manual", {
    p_shop: shop, p_service: service, p_service_revision: serviceRevision, p_policy: policy,
    p_key: key, p_start: start, p_name: name, p_phone: phone, p_channel: channel,
  });
  if (error) return failure(error);
  if (typeof data !== "string" || !isUuid(data)) return { error: "예약 결과를 확인할 수 없어요. 같은 화면에서 다시 시도해 주세요." };
  redirectSaved(`/dashboard/schedule/${data}?saved=1`);
}

export async function changeBooking(_state: SettingsState, form: FormData): Promise<SettingsState> {
  if (!(await sameOrigin())) return inputError;
  const { supabase } = await requireBusiness(true);
  const shop = field(form, "shop");
  const booking = field(form, "booking");
  const key = field(form, "requestId");
  const revision = version(field(form, "revision"));
  const operation = field(form, "operation");
  const start = operation === "move" ? startsInSeoul(field(form, "start")) : null;
  const reason = field(form, "reason");
  if (!isUuid(shop) || !isUuid(booking) || !isUuid(key) || !revision
    || !["move", "cancel", "complete", "no_show"].includes(operation)
    || (operation === "move" && !start) || (operation === "cancel" && !reason)
    || reason.length > 200 || /[\p{Cc}]/u.test(reason)) return inputError;

  const { error } = await supabase.rpc("r6_change", {
    p_shop: shop, p_booking: booking, p_revision: revision, p_operation: operation,
    p_start: start, p_reason: reason || null, p_key: key,
  });
  if (error) return failure(error);
  redirectSaved(`/dashboard/schedule/${booking}?saved=1`);
}

export async function createBlock(_state: SettingsState, form: FormData): Promise<SettingsState> {
  if (!(await sameOrigin())) return inputError;
  const { supabase } = await requireBusiness(true);
  const shop = field(form, "shop");
  const key = field(form, "requestId");
  const start = startsInSeoul(field(form, "start"));
  const end = startsInSeoul(field(form, "end"));
  const reason = field(form, "reason");
  if (!isUuid(shop) || !isUuid(key) || !start || !end || Date.parse(start) >= Date.parse(end)
    || !reason || reason.length > 120 || /[\p{Cc}]/u.test(reason)) return inputError;

  const { error } = await supabase.rpc("r6_block", {
    p_shop: shop, p_key: key, p_start: start, p_end: end, p_reason: reason,
  });
  if (error) return failure(error);
  redirectSaved(`/dashboard/schedule?date=${start.slice(0, 10)}&saved=1`);
}

export async function releaseBlock(_state: SettingsState, form: FormData): Promise<SettingsState> {
  if (!(await sameOrigin())) return inputError;
  const { supabase } = await requireBusiness(true);
  const shop = field(form, "shop");
  const block = field(form, "block");
  const date = field(form, "date");
  if (!isUuid(shop) || !isUuid(block) || !validDay(date)) return inputError;

  const { error } = await supabase.rpc("r6_unblock", { p_shop: shop, p_block: block });
  if (error) return failure(error);
  redirectSaved(`/dashboard/schedule?date=${date}&saved=1`);
}

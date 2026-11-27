"use server";

import { revalidatePath } from "next/cache";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { requireBusiness } from "../../lib/dashboard/server";
import { clockMinute, isUuid, maxBookingWindowDays, type Period, type SettingsState } from "../../lib/dashboard/settings";

const requestError = { error: "페이지를 다시 열고 저장해 주세요." };
const messages: Record<string, string> = {
  r5_service_key: "이미 처리된 시술 등록이에요. 시술 목록을 확인해 주세요.",
  r4_owner: "이 설정을 변경할 권한이 없어요.",
  r4_stale: "다른 화면에서 설정이 변경됐어요. 새로고침한 뒤 다시 입력해 주세요.",
  r4_slug_taken: "이미 사용 중인 공개 주소예요. 다른 값을 입력해 주세요.",
  r4_shop_input: "샵 이름과 공개 주소를 확인해 주세요.",
  r4_service_input: "시술 시간과 가격, 예약금 및 공개 상태를 확인해 주세요.",
  r4_hours_input: "시작과 종료를 15분 단위로 입력해 주세요. 종료는 시작보다 늦어야 해요.",
  r4_hours_overlap: "같은 요일의 영업시간 또는 휴식시간이 겹쳐요.",
  r4_break_outside: "휴식시간을 영업시간 안에 설정해 주세요.",
  r4_policy_input: "예약 가능 기간은 오늘을 포함해 최대 90일이에요. 예약 정책의 숫자와 안내 문구를 확인해 주세요.",
  r4_bank_input: "은행, 계좌번호, 예금주를 모두 올바르게 입력해 주세요.",
  r4_deposit_requirements: "예약금이 있는 시술을 공개하려면 입금 계좌와 예약금·취소 안내를 모두 등록해야 해요.",
};

function failure(error: { code: string; message: string }): SettingsState {
  if (error.code === "PGRST202") return { error: "샵 설정 기능이 아직 준비되지 않았어요." };
  return {
    error: Object.hasOwn(messages, error.message)
      ? messages[error.message]
      : "설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.",
  };
}

async function fromForm() {
  const request = await headers();
  const origin = request.get("origin");
  // Next.js matches the Origin host to the request host.
  return Boolean(origin && origin !== "null" && request.get("sec-fetch-site") !== "cross-site");
}

function text(form: FormData, name: string) {
  const value = form.get(name);
  return typeof value === "string" ? value.trim() : "";
}

function integer(form: FormData, name: string, minimum = 0) {
  const raw = text(form, name);
  const value = Number(raw);
  return /^[0-9]{1,10}$/.test(raw) && value >= minimum && value <= 2_147_483_647 ? value : null;
}

function saveComplete(path: string): never {
  revalidatePath("/dashboard", "layout");
  redirect(path);
}

export async function saveShop(_state: SettingsState, form: FormData): Promise<SettingsState> {
  if (!(await fromForm())) return requestError;
  const { supabase } = await requireBusiness(true);
  const shop = text(form, "shop");
  const revision = integer(form, "revision", 1);
  const name = text(form, "name");
  const slug = text(form, "slug").toLowerCase();

  if (!name || name.length > 80 || slug.length < 3 || slug.length > 60 ||
    !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug) || (shop && (!isUuid(shop) || !revision))) {
    return { error: messages.r4_shop_input };
  }

  const { error } = await supabase.rpc("r4_save_shop", {
    p_shop_id: shop || null, p_revision: shop ? revision : null, p_name: name, p_slug: slug,
  });
  if (error) return failure(error);
  saveComplete("/dashboard?saved=1");
}

export async function saveService(_state: SettingsState, form: FormData): Promise<SettingsState> {
  if (!(await fromForm())) return requestError;
  const { supabase } = await requireBusiness(true);
  const shop = text(form, "shop");
  const service = text(form, "service");
  const requestId = text(form, "requestId");
  const revision = integer(form, "revision", 1);
  const name = text(form, "name");
  const description = text(form, "description");
  const duration = integer(form, "duration", 15);
  const buffer = integer(form, "buffer");
  const price = integer(form, "price");
  const deposit = integer(form, "deposit");
  const state = text(form, "state");

  if (!isUuid(shop) || (service ? !isUuid(service) || !revision : !isUuid(requestId)) ||
    !name || name.length > 80 || description.length > 1000 ||
    duration === null || buffer === null || duration % 15 !== 0 || buffer % 15 !== 0 ||
    duration + buffer > 1440 || price === null || deposit === null || deposit > price ||
    !["private", "public", "inactive"].includes(state)) {
    return { error: messages.r4_service_input };
  }

  const fields = {
    p_shop_id: shop, p_name: name, p_description: description, p_duration: duration, p_buffer: buffer,
    p_price: price, p_deposit: deposit, p_state: state,
  };
  const { error } = service
    ? await supabase.rpc("r4_save_service", { ...fields, p_service_id: service, p_revision: revision })
    : await supabase.rpc("r5_create_service", { ...fields, p_request_id: requestId });
  if (error) return failure(error);
  saveComplete("/dashboard/services?saved=1");
}

function readPeriods(raw: string): Period[] | null {
  if (raw.length > 16000) return null;
  let payload: unknown;
  try {
    payload = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!Array.isArray(payload) || payload.length > 96) return null;

  const result: Period[] = [];
  for (const item of payload) {
    if (!item || typeof item !== "object") return null;
    const { day, kind, start, end } = item;
    const startMinute = clockMinute(start);
    const endMinute = clockMinute(end);
    if (!Number.isInteger(day) || day < 1 || day > 7 ||
      (kind !== "opening" && kind !== "break") ||
      startMinute === null || endMinute === null || startMinute >= endMinute) return null;
    result.push({ iso_weekday: day, period_kind: kind, start_minute: startMinute, end_minute: endMinute });
  }
  return result;
}

export async function saveHours(_state: SettingsState, form: FormData): Promise<SettingsState> {
  if (!(await fromForm())) return requestError;
  const { supabase } = await requireBusiness(true);
  const shop = text(form, "shop");
  const revision = integer(form, "revision", 1);
  const periods = readPeriods(text(form, "periods"));
  if (!isUuid(shop) || revision === null || !periods) return { error: messages.r4_hours_input };

  const { error } = await supabase.rpc("r4_save_hours", {
    p_shop_id: shop, p_revision: revision, p_periods: periods,
  });
  if (error) return failure(error);
  saveComplete("/dashboard/hours?saved=1");
}

export async function savePolicy(_state: SettingsState, form: FormData): Promise<SettingsState> {
  if (!(await fromForm())) return requestError;
  const { supabase } = await requireBusiness(true);
  const shop = text(form, "shop");
  const revision = integer(form, "revision", 1);
  const notice = integer(form, "notice");
  const window = integer(form, "window", 1);
  const cancellationNotice = integer(form, "cancellationNotice");
  const report = integer(form, "report");
  const cancellationPolicy = text(form, "cancellationPolicy");
  const depositPolicy = text(form, "depositPolicy");
  const bank = text(form, "bank");
  const accountNumber = text(form, "accountNumber");
  const accountHolder = text(form, "accountHolder");

  if (!isUuid(shop) || revision === null || notice === null || window === null || window > maxBookingWindowDays ||
    cancellationNotice === null || report === null || ![30, 60, 120].includes(report) ||
    cancellationPolicy.length > 2000 || depositPolicy.length > 2000) {
    return { error: messages.r4_policy_input };
  }

  const digits = accountNumber.replaceAll("-", "").length;
  if ((bank || accountNumber || accountHolder) &&
    (!bank || bank.length > 60 || !accountHolder || accountHolder.length > 60 ||
      accountNumber.length > 40 || !/^[0-9]+(-[0-9]+)*$/.test(accountNumber) || digits < 5 || digits > 24)) {
    return { error: messages.r4_bank_input };
  }

  const { error } = await supabase.rpc("r4_save_policy", {
    p_shop_id: shop, p_revision: revision, p_notice: notice, p_window: window,
    p_cancellation_notice: cancellationNotice, p_report: report,
    p_cancellation_policy: cancellationPolicy, p_deposit_policy: depositPolicy,
    p_bank: bank, p_account_number: accountNumber, p_account_holder: accountHolder,
  });
  if (error) return failure(error);
  saveComplete("/dashboard/policy?saved=1");
}

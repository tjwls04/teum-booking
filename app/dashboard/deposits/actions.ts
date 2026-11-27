"use server";

import { revalidatePath } from "next/cache";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { requireBusiness } from "../../../lib/dashboard/server";
import { isUuid, type SettingsState } from "../../../lib/dashboard/settings";

const messages: Record<string, string> = {
  r7_input: "직접 확인 여부, 금액과 사유를 입력해 주세요.",
  r7_missing: "이 예약의 금전 상태를 변경할 권한이 없어요.",
  r7_key: "이미 처리된 요청과 내용이 달라요. 상태를 다시 확인해 주세요.",
  r7_stale: "예약 또는 금전 상태가 변경됐어요. 새로고침한 뒤 다시 확인해 주세요.",
  r7_state: "현재 상태에서는 이 처리를 기록할 수 없어요.",
  r7_amount: "기록한 입금액에서 이전 환불액을 뺀 금액을 넘길 수 없어요.",
  r7_reason: "입금액이 예약금과 다르면 사유를 입력해 주세요.",
  r7_duplicate: "같은 금액과 사유가 이미 기록됐어요.",
};
const completed = new Set([
  "deposit_verified", "deposit_verified_after_close", "deposit_discrepancy", "manual_refund_recorded", "no_refund_recorded",
]);

function field(form: FormData, name: string) {
  const value = form.get(name);
  return typeof value === "string" ? value.trim() : "";
}

export async function recordDeposit(_state: SettingsState, form: FormData): Promise<SettingsState> {
  const request = await headers();
  const origin = request.get("origin");
  if (!origin || origin === "null" || request.get("sec-fetch-site") === "cross-site") {
    return { error: "페이지를 다시 열고 시도해 주세요." };
  }

  const { supabase } = await requireBusiness(true);
  const shop = field(form, "shop");
  const booking = field(form, "booking");
  const key = field(form, "requestId");
  const revision = Number(field(form, "revision"));
  const operation = field(form, "operation");
  const rawAmount = field(form, "amount");
  const amount = operation === "no_refund" ? 0 : Number(rawAmount);
  const reason = field(form, "reason");
  const checked = form.get("checked") === "yes";

  if (!isUuid(shop) || !isUuid(booking) || !isUuid(key)
    || !Number.isInteger(revision) || revision < 1 || revision > 2_147_483_647
    || !["confirm", "receipt", "refund", "no_refund"].includes(operation) || !checked
    || (operation !== "no_refund" && (!/^[0-9]{1,10}$/.test(rawAmount) || amount <= 0 || amount > 2_147_483_647))
    || (operation !== "confirm" && !reason) || reason.length > 200 || /[\p{Cc}]/u.test(reason)) {
    return { error: messages.r7_input };
  }

  const { data, error } = await supabase.rpc("r7_record", {
    p_shop: shop, p_booking: booking, p_revision: revision, p_operation: operation, p_amount: amount,
    p_reason: reason || null, p_checked: checked, p_key: key,
  });
  if (error) {
    return { error: error.message === "r4_owner" ? messages.r7_missing : "저장 결과를 확인하지 못했어요. 같은 화면에서 다시 시도해 주세요." };
  }
  if (typeof data !== "string" || !completed.has(data)) {
    return { error: typeof data === "string" && Object.hasOwn(messages, data) ? messages[data] : "처리 결과를 확인할 수 없어요." };
  }

  revalidatePath("/dashboard", "layout");
  redirect(`/dashboard/deposits/${booking}?saved=1`);
}

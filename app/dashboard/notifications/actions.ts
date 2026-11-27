"use server";

import { revalidatePath } from "next/cache";
import { requireShop } from "../../../lib/dashboard/server";
import { isUuid } from "../../../lib/dashboard/settings";
import { validPushEndpoint, validSubscriptionKeys, vapidConfig } from "../../../lib/notifications/push";

const requestError = "알림 설정을 저장하지 못했어요. 다시 시도해 주세요.";

export async function updateRead(_state: string | null, form: FormData) {
  const id = form.get("id");
  const read = form.get("read");
  if ((id !== "all" && (typeof id !== "string" || !isUuid(id))) || (read !== "yes" && read !== "no")
      || (id === "all" && read !== "yes")) return requestError;

  const { supabase, shop } = await requireShop();
  const { error } = await supabase.rpc("r8_read", { p_shop: shop.id, p_id: id === "all" ? null : id, p_read: read === "yes" });
  if (error) return "읽음 상태를 저장하지 못했어요. 다시 시도해 주세요.";
  revalidatePath("/dashboard", "layout");
  return null;
}

export async function setPushEnabled(_state: string | null, form: FormData) {
  const enabled = form.get("enabled");
  if (enabled !== "yes" && enabled !== "no") return requestError;
  const { supabase, shop } = await requireShop();
  const { error } = await supabase.rpc("r8_set_enabled", { p_shop: shop.id, p_enabled: enabled === "yes" });
  if (error) return requestError;
  revalidatePath("/dashboard/notifications");
  return null;
}

export async function registerPush(endpoint: string | undefined, p256dh: string | undefined, auth: string | undefined) {
  if (!vapidConfig() || !validPushEndpoint(endpoint) || !validSubscriptionKeys(p256dh, auth)) {
    return "지원하는 브라우저에서 푸시 구독을 다시 확인해 주세요.";
  }
  const { supabase, shop } = await requireShop();
  const { error } = await supabase.rpc("r8_register", { p_shop: shop.id, p_endpoint: endpoint, p_p256dh: p256dh, p_auth: auth });
  if (error?.message === "r8_device_limit") return "최대 10대까지 연결할 수 있어요. 사용하지 않는 기기를 먼저 해제해 주세요.";
  if (error?.message === "r8_device_conflict") return "다른 사업자 계정에서 이 기기를 먼저 해제해 주세요.";
  if (error) return requestError;
  revalidatePath("/dashboard/notifications");
  return null;
}

export async function removeCurrentPush(endpoint: string) {
  if (!validPushEndpoint(endpoint)) return requestError;
  const { supabase, shop } = await requireShop();
  const { error } = await supabase.rpc("r8_remove", { p_shop: shop.id, p_id: null, p_endpoint: endpoint });
  if (error) return requestError;
  revalidatePath("/dashboard/notifications");
  return null;
}

export async function removePushDevice(_state: string | null, form: FormData) {
  const id = form.get("id");
  if (typeof id !== "string" || !isUuid(id)) return requestError;
  const { supabase, shop } = await requireShop();
  const { error } = await supabase.rpc("r8_remove", { p_shop: shop.id, p_id: id, p_endpoint: null });
  if (error) return requestError;
  revalidatePath("/dashboard/notifications");
  return null;
}

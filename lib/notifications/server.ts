import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import { isUuid } from "../dashboard/settings";
import { type InboxItem, notificationLabels, notificationPath, notificationTarget } from "./types";

export async function resolveNotification(client: SupabaseClient, shopId: string, id: string) {
  if (!notificationPath(id)) return "/dashboard/notifications";
  const { data, error } = await client.rpc("r8_target", { p_shop: shopId, p_id: id });
  const item = data as Pick<InboxItem, "booking_id" | "kind"> | null;
  return !error && item && isUuid(item.booking_id) && Object.hasOwn(notificationLabels, item.kind)
    ? notificationTarget(item)
    : "/dashboard/notifications";
}

import "server-only";

import { redirect } from "next/navigation";
import { cache } from "react";
import { isBusinessUser } from "../auth/business-user";
import { createClient } from "../supabase/server";

type Shop = {
  id: string;
  name: string;
  slug: string;
  policy_revision: number;
  min_notice_minutes: number;
  booking_window_days: number;
  cancellation_notice_minutes: number;
  deposit_report_minutes: number;
  cancellation_policy: string;
  deposit_policy: string;
};

export type Service = {
  id: string;
  name: string;
  description: string;
  duration_minutes: number;
  buffer_minutes: number;
  price_krw: number;
  deposit_krw: number;
  is_active: boolean;
  is_public: boolean;
  revision: number;
};

export const serviceColumns =
  "id, name, description, duration_minutes, buffer_minutes, price_krw, deposit_krw, is_active, is_public, revision";

export async function requireBusiness(writeCookies = false) {
  const supabase = await createClient(writeCookies);
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !isBusinessUser(user)) redirect("/auth/login");
  return { supabase, user };
}

export const dashboardContext = cache(async () => {
  const { supabase, user } = await requireBusiness();
  const { data: shop, error } = await supabase
    .from("shops")
    .select(
      "id, name, slug, policy_revision, min_notice_minutes, booking_window_days, cancellation_notice_minutes, deposit_report_minutes, cancellation_policy, deposit_policy",
    )
    .eq("owner_user_id", user.id)
    .maybeSingle<Shop>();
  return { supabase, user, shop, error };
});

export async function requireShop() {
  const { supabase, shop, error } = await dashboardContext();
  if (error) throw new Error("샵 정보를 불러올 수 없습니다.");
  if (!shop) redirect("/dashboard");
  return { supabase, shop };
}

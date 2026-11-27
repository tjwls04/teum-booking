import { redirect } from "next/navigation";
import { requireShop } from "../../../../../lib/dashboard/server";
import { resolveNotification } from "../../../../../lib/notifications/server";

export async function GET(_request: Request, { params }: RouteContext<"/dashboard/notifications/open/[id]">) {
  const { supabase, shop } = await requireShop();
  const { id } = await params;
  redirect(await resolveNotification(supabase, shop.id, id));
}

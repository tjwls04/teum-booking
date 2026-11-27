import type { User } from "@supabase/supabase-js";

export function isBusinessUser(user: User | null): user is User & { email: string } {
  return Boolean(user?.email && user.email_confirmed_at && user.is_anonymous !== true);
}

import type { Metadata } from "next";
import type { ReactNode } from "react";
import { dashboardContext } from "../../lib/dashboard/server";
import { logOut } from "../auth/actions";
import { AuthForm } from "../auth/auth-form";
import { DashboardNav } from "./dashboard-nav";
import styles from "./dashboard.module.css";
import { SessionHistory } from "./session-history";

export const metadata: Metadata = {
  title: "사업자 대시보드",
  robots: { index: false, follow: false },
  manifest: "/manifest.webmanifest",
  icons: { apple: "/app-icon-180.png" },
};

export default async function DashboardLayout({ children }: { children: ReactNode }) {
  const { supabase, user, shop, error } = await dashboardContext();
  const count = shop ? await supabase.rpc("r8_unread", { p_shop: shop.id }) : null;
  const unread = typeof count?.data === "number" ? count.data : 0;

  return (
    <main className={`shell ${styles.main}`}>
      <SessionHistory />
      <div className={styles.account}>
        <div>
          <p className="font-semibold text-pine">{shop?.name ?? "사업자 대시보드"}</p>
          <p className="text-sm text-muted">{user.email}</p>
        </div>
        <AuthForm action={logOut} mode="logout" submitLabel="로그아웃" />
      </div>
      <DashboardNav hasShop={Boolean(shop)} unread={unread} />
      <div className={styles.content}>
        {error ? <p className="auth-error" role="alert">샵 정보를 불러오지 못했어요. 새로고침해 주세요.</p> : children}
      </div>
    </main>
  );
}

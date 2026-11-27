"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import styles from "./dashboard.module.css";

const links = [
  ["/dashboard", "샵 정보"],
  ["/dashboard/schedule", "예약 관리"],
  ["/dashboard/deposits", "예약금"],
  ["/dashboard/notifications", "알림"],
  ["/dashboard/services", "시술"],
  ["/dashboard/hours", "영업시간"],
  ["/dashboard/policy", "예약 정책"],
] as const;

export function DashboardNav({ hasShop, unread }: { hasShop: boolean; unread: number }) {
  const path = usePathname();
  return (
    <nav aria-label="사업자 설정" className={styles.navigation}>
      {links.slice(0, hasShop ? undefined : 1).map(([href, label]) => (
        <Link prefetch={false} key={href} href={href} className="text-link"
          aria-current={path === href || (href !== "/dashboard" && path.startsWith(`${href}/`)) ? "page" : undefined}>
          {href === "/dashboard/notifications" && unread > 0 ? `알림 ${unread}건` : label}
        </Link>
      ))}
    </nav>
  );
}

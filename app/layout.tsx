import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "틈예약 | 1인 샵 예약 관리",
    template: "%s | 틈예약",
  },
  description: "샵인샵과 1인 프리랜서 사업자를 위한 예약 관리 서비스.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ko">
      <body>
        <header className="border-b border-rule">
          <div className="shell flex min-h-18 items-center justify-between gap-4">
            <Link href="/" className="wordmark">
              <span className="wordmark-symbol" aria-hidden="true" />
              틈예약
            </Link>
            <nav aria-label="주 메뉴" className="site-nav">
              <Link href="/#about" className="intro-link">서비스 소개</Link>
              <Link href="/setup" className="intro-link">개발 상태</Link>
              <Link href="/auth/login" className="status-link">사업자 로그인</Link>
            </nav>
          </div>
        </header>
        {children}
        <footer className="border-t border-rule">
          <div className="shell flex min-h-20 flex-wrap items-center justify-between gap-x-6 gap-y-2 py-4">
            <Link href="/" className="wordmark">틈예약</Link>
            <p className="text-sm text-muted">샵인샵·1인 프리랜서를 위한 예약 관리</p>
          </div>
        </footer>
      </body>
    </html>
  );
}

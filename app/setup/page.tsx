import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "개발 상태",
  description: "틈예약의 로컬 개발 단계와 연결 상태 안내.",
};

export default function SetupPage() {
  return (
    <main className="shell setup-page">
      <Link href="/" className="text-link">
        <span aria-hidden="true">←</span> 홈으로
      </Link>
      <div className="setup-content">
        <h1 className="section-title">개발 상태</h1>
        <p className="hero-description">현재 구현된 기능과 로컬 서버 응답을 확인할 수 있습니다.</p>
        <dl className="setup-list">
          <div>
            <dt>로컬 서버</dt>
            <dd><a href="/api/health" className="text-link">런타임 응답 확인 <span aria-hidden="true">↗</span></a></dd>
          </div>
          <div>
            <dt>데이터베이스</dt>
            <dd>개발 DB 스키마 적용됨</dd>
          </div>
          <div>
            <dt>사업자 인증 및 로그인</dt>
            <dd><Link href="/auth/login" className="text-link">사업자 로그인</Link></dd>
          </div>
          <div>
            <dt>예약 및 결제</dt>
            <dd>구현 전</dd>
          </div>
          <div>
            <dt>알림</dt>
            <dd>구현 전</dd>
          </div>
        </dl>
      </div>
    </main>
  );
}

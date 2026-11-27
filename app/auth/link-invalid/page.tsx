import type { Metadata } from "next";
import Link from "next/link";
import { AuthScreen } from "../auth-screen";

export const metadata: Metadata = { title: "이메일 링크 확인" };

export default function InvalidLinkPage() {
  return (
    <AuthScreen title="이메일 링크를 사용할 수 없어요" description="링크가 만료되었거나 이미 사용되었을 수 있어요. 새 메일을 요청해 주세요.">
      <nav aria-label="이메일 다시 요청" className="auth-links">
        <Link href="/auth/resend" className="text-link">인증 메일 다시 보내기</Link>
        <Link href="/auth/forgot-password" className="text-link">비밀번호 재설정</Link>
        <Link href="/auth/login" className="text-link">로그인으로 돌아가기</Link>
      </nav>
    </AuthScreen>
  );
}

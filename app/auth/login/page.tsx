import type { Metadata } from "next";
import Link from "next/link";
import { notificationPath } from "../../../lib/notifications/types";
import { logIn } from "../actions";
import { AuthForm } from "../auth-form";
import { AuthScreen } from "../auth-screen";

export const metadata: Metadata = { title: "사업자 로그인" };

const notices = {
  confirmed: "이메일 인증을 완료했어요. 비밀번호로 로그인해 주세요.",
  "password-reset": "비밀번호를 변경했어요. 새 비밀번호로 로그인해 주세요.",
  "signed-out": "로그아웃했어요.",
} as const;

export default async function LoginPage({ searchParams }: PageProps<"/auth/login">) {
  const { notice, notification } = await searchParams;
  const message = typeof notice === "string" && Object.hasOwn(notices, notice)
    ? notices[notice as keyof typeof notices]
    : null;

  return (
    <AuthScreen title="사업자 로그인" description="틈예약 사업자 계정으로 로그인하세요.">
      {message && <p className="auth-notice mb-5" role="status">{message}</p>}
      <AuthForm action={logIn} mode="login" submitLabel="로그인" notification={notificationPath(notification) && typeof notification === "string" ? notification : undefined} />
      <nav aria-label="계정 메뉴" className="auth-links">
        <Link href="/auth/signup" className="text-link">사업자 회원가입</Link>
        <Link href="/auth/forgot-password" className="text-link">비밀번호 재설정</Link>
        <Link href="/auth/resend" className="text-link">인증 메일 다시 보내기</Link>
      </nav>
    </AuthScreen>
  );
}

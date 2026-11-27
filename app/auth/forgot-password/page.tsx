import type { Metadata } from "next";
import Link from "next/link";
import { requestPasswordReset } from "../actions";
import { AuthForm } from "../auth-form";
import { AuthScreen } from "../auth-screen";

export const metadata: Metadata = { title: "비밀번호 재설정" };

const notices = {
  same: "기존과 다른 비밀번호가 필요해요. 재설정 메일을 다시 요청해 주세요.",
  weak: "입력한 비밀번호가 보안 기준을 충족하지 않아요. 메일을 다시 요청한 뒤 다른 비밀번호를 사용해 주세요.",
  retry: "비밀번호를 변경하지 못했어요. 재설정 메일을 다시 요청해 주세요.",
} as const;

export default async function ForgotPasswordPage({ searchParams }: PageProps<"/auth/forgot-password">) {
  const { notice } = await searchParams;
  const message = typeof notice === "string" && Object.hasOwn(notices, notice)
    ? notices[notice as keyof typeof notices]
    : null;

  return (
    <AuthScreen title="비밀번호 재설정" description="가입한 이메일로 비밀번호를 재설정하는 링크를 보내 드려요.">
      {message && <p className="auth-error mb-5" role="alert">{message}</p>}
      <AuthForm action={requestPasswordReset} mode="email" submitLabel="재설정 메일 보내기" />
      <div className="auth-links">
        <Link href="/auth/login" className="text-link">로그인으로 돌아가기</Link>
      </div>
    </AuthScreen>
  );
}

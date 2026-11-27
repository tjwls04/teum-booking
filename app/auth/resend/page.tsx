import type { Metadata } from "next";
import Link from "next/link";
import { resendEmail } from "../actions";
import { AuthForm } from "../auth-form";
import { AuthScreen } from "../auth-screen";

export const metadata: Metadata = { title: "인증 메일 다시 보내기" };

export default function ResendPage() {
  return (
    <AuthScreen title="인증 메일 다시 보내기" description="가입할 때 입력한 사업자 이메일을 사용해 주세요.">
      <AuthForm action={resendEmail} mode="email" submitLabel="인증 메일 보내기" />
      <div className="auth-links">
        <Link href="/auth/login" className="text-link">로그인으로 돌아가기</Link>
      </div>
    </AuthScreen>
  );
}

import type { Metadata } from "next";
import Link from "next/link";
import { signUp } from "../actions";
import { AuthForm } from "../auth-form";
import { AuthScreen } from "../auth-screen";

export const metadata: Metadata = { title: "사업자 회원가입" };

export default function SignupPage() {
  return (
    <AuthScreen title="사업자 회원가입" description="가입 후 이메일 인증을 완료하면 로그인할 수 있어요.">
      <AuthForm action={signUp} mode="signup" submitLabel="가입하기" />
      <div className="auth-links">
        <Link href="/auth/login" className="text-link">로그인으로 돌아가기</Link>
      </div>
    </AuthScreen>
  );
}

import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { readChallenge } from "../../../lib/auth/challenge";
import { resetPassword } from "../actions";
import { AuthForm } from "../auth-form";
import { AuthScreen } from "../auth-screen";

export const metadata: Metadata = { title: "새 비밀번호 설정" };

export default async function ResetPasswordPage() {
  if (!(await readChallenge("recovery"))) redirect("/auth/link-invalid");

  return (
    <AuthScreen title="새 비밀번호 설정" description="다음 로그인부터 사용할 비밀번호를 입력해 주세요.">
      <AuthForm action={resetPassword} mode="reset" submitLabel="비밀번호 변경하기" />
    </AuthScreen>
  );
}

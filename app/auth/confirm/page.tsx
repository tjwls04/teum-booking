import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { readChallenge } from "../../../lib/auth/challenge";
import { confirmEmail } from "../actions";
import { AuthForm } from "../auth-form";
import { AuthScreen } from "../auth-screen";

export const metadata: Metadata = { title: "사업자 이메일 인증" };

export default async function ConfirmPage() {
  if (!(await readChallenge("email"))) redirect("/auth/link-invalid");

  return (
    <AuthScreen title="사업자 이메일 인증" description="본인이 가입을 요청했다면 아래 버튼을 눌러 인증을 완료하세요.">
      <AuthForm action={confirmEmail} mode="confirm" submitLabel="이메일 인증 완료하기" />
    </AuthScreen>
  );
}

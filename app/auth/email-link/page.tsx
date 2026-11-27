import type { Metadata } from "next";
import { AuthScreen } from "../auth-screen";
import { EmailLink } from "./view";

export const metadata: Metadata = { title: "이메일 링크 확인" };

export default function EmailLinkPage() {
  return (
    <AuthScreen title="이메일 링크 확인" description="확인 화면으로 이동합니다.">
      <EmailLink />
      <noscript><p className="auth-error">이메일 링크를 열려면 브라우저에서 JavaScript를 허용해 주세요.</p></noscript>
    </AuthScreen>
  );
}

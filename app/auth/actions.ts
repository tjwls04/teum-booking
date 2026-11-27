"use server";

import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { isBusinessUser } from "../../lib/auth/business-user";
import { challengeCookie, challengeCookieOptions, clearChallenge, parseChallenge, readChallenge } from "../../lib/auth/challenge";
import {
  type AuthState,
  readEmail,
  readPassword,
  validateNewPassword,
} from "../../lib/auth/form";
import { resolveNotification } from "../../lib/notifications/server";
import { notificationPath } from "../../lib/notifications/types";
import { createClient, createEmailClient } from "../../lib/supabase/server";

const invalidOrigin = { message: "페이지를 다시 열어 시도해 주세요." };
const invalidEmail = {
  field: "email",
  message: "올바른 이메일 주소를 입력해 주세요.",
} as const;
const requestFailed = {
  message: "요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.",
};
const signupSent = {
  success: true,
  message:
    "인증이 필요한 이메일이라면 확인 메일이 도착합니다. 받은편지함과 스팸함을 확인해 주세요.",
};

async function hasBrowserOrigin() {
  const requestHeaders = await headers();
  const origin = requestHeaders.get("origin");
  // Next.js checks the origin host against the app host; also decline missing and opaque origins.
  return Boolean(
    origin &&
    origin !== "null" &&
    requestHeaders.get("sec-fetch-site") !== "cross-site",
  );
}

export async function prepareEmailLink(type: unknown, token: unknown) {
  if (!(await hasBrowserOrigin()) || typeof type !== "string" || typeof token !== "string") return null;
  const challenge = parseChallenge(type, token);
  if (!challenge) return null;
  (await cookies()).set(challengeCookie, `${challenge.type}:${challenge.token}`, challengeCookieOptions);
  return challenge.type === "email" ? "/auth/confirm" : "/auth/reset-password";
}

export async function logIn(
  _state: AuthState,
  form: FormData,
): Promise<AuthState> {
  if (!(await hasBrowserOrigin())) return invalidOrigin;
  const email = readEmail(form);
  if (!email) return invalidEmail;
  const password = readPassword(form);
  if (!password || password.length > 1024) {
    return { field: "password", message: "비밀번호를 확인해 주세요." };
  }

  const supabase = await createClient(true);
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });
  if (error) {
    if (error.code === "email_not_confirmed") {
      return {
        message:
          "이메일 인증을 완료한 뒤 로그인해 주세요. 인증 메일을 다시 보낼 수 있어요.",
      };
    }
    if (error.code === "invalid_credentials") {
      return { message: "이메일 또는 비밀번호를 확인해 주세요." };
    }
    return requestFailed;
  }
  if (!data.session || !isBusinessUser(data.user)) {
    await supabase.auth.signOut({ scope: "local" });
    return { message: "인증한 사업자 이메일로 로그인해 주세요." };
  }
  const notification = form.get("notification");
  if (typeof notification === "string" && notificationPath(notification)) {
    const { data: shop } = await supabase.from("shops").select("id").eq("owner_user_id", data.user.id).maybeSingle();
    if (shop) redirect(await resolveNotification(supabase, shop.id, notification));
  }
  redirect("/dashboard");
}

export async function signUp(
  _state: AuthState,
  form: FormData,
): Promise<AuthState> {
  if (!(await hasBrowserOrigin())) return invalidOrigin;
  const email = readEmail(form);
  if (!email) return invalidEmail;
  const password = readPassword(form);
  const validation = validateNewPassword(password, form);
  if (validation) return validation;

  const supabase = createEmailClient();
  const { data, error } = await supabase.auth.signUp({ email, password });
  if (data.session) {
    await supabase.auth.signOut({ scope: "local" });
    return {
      message: "서비스의 이메일 인증 설정을 확인한 뒤 다시 시도해 주세요.",
    };
  }
  if (error?.code === "weak_password") {
    return {
      field: "password",
      message: "더 안전한 비밀번호로 다시 입력해 주세요.",
    };
  }
  if (
    error &&
    ![
      "user_already_exists",
      "email_exists",
      "over_email_send_rate_limit",
    ].includes(error.code ?? "")
  ) {
    const diagnostic = {
      kind: error.name,
      code: error.code && /^[a-z_]{1,64}$/.test(error.code) ? error.code : undefined,
      status: error.status,
    };
    console.error(`[Signup error] ${JSON.stringify(diagnostic)}`);
    return requestFailed;
  }
  return signupSent;
}

export async function resendEmail(
  _state: AuthState,
  form: FormData,
): Promise<AuthState> {
  if (!(await hasBrowserOrigin())) return invalidOrigin;
  const email = readEmail(form);
  if (!email) return invalidEmail;

  const { error } = await createEmailClient().auth.resend({
    type: "signup",
    email,
  });
  if (
    error &&
    ![
      "user_not_found",
      "over_email_send_rate_limit",
      "email_already_confirmed",
    ].includes(error.code ?? "")
  ) {
    return requestFailed;
  }
  return signupSent;
}

export async function requestPasswordReset(
  _state: AuthState,
  form: FormData,
): Promise<AuthState> {
  if (!(await hasBrowserOrigin())) return invalidOrigin;
  const email = readEmail(form);
  if (!email) return invalidEmail;

  const { error } = await createEmailClient().auth.resetPasswordForEmail(email);
  if (
    error &&
    !["user_not_found", "over_email_send_rate_limit"].includes(error.code ?? "")
  ) {
    return requestFailed;
  }
  return {
    success: true,
    message:
      "등록된 이메일이라면 재설정 메일이 도착합니다. 받은편지함과 스팸함을 확인해 주세요.",
  };
}

export async function confirmEmail(
  _state: AuthState,
  _form: FormData,
): Promise<AuthState> {
  if (!(await hasBrowserOrigin())) return invalidOrigin;
  const token = await readChallenge("email");
  if (!token) redirect("/auth/link-invalid");
  await clearChallenge();

  const supabase = createEmailClient();
  const { data, error } = await supabase.auth.verifyOtp({
    token_hash: token,
    type: "email",
  });
  if (data.session) await supabase.auth.signOut({ scope: "local" });
  if (error || !isBusinessUser(data.user)) redirect("/auth/link-invalid");
  redirect("/auth/login?notice=confirmed");
}

export async function resetPassword(
  _state: AuthState,
  form: FormData,
): Promise<AuthState> {
  if (!(await hasBrowserOrigin())) return invalidOrigin;
  const token = await readChallenge("recovery");
  if (!token) redirect("/auth/link-invalid");

  const password = readPassword(form);
  const validation = validateNewPassword(password, form);
  if (validation) return validation;
  await clearChallenge();

  const supabase = createEmailClient();
  const { data, error } = await supabase.auth.verifyOtp({
    token_hash: token,
    type: "recovery",
  });
  if (error || !data.session || !isBusinessUser(data.user)) {
    if (data.session) await supabase.auth.signOut({ scope: "local" });
    redirect("/auth/link-invalid");
  }

  const { error: updateError } = await supabase.auth.updateUser({ password });
  await supabase.auth.signOut({ scope: "local" });
  if (updateError?.code === "same_password")
    redirect("/auth/forgot-password?notice=same");
  if (updateError?.code === "weak_password")
    redirect("/auth/forgot-password?notice=weak");
  if (updateError) redirect("/auth/forgot-password?notice=retry");
  redirect("/auth/login?notice=password-reset");
}

export async function logOut(
  _state: AuthState,
  _form: FormData,
): Promise<AuthState> {
  if (!(await hasBrowserOrigin())) return invalidOrigin;

  const { error } = await (
    await createClient(true)
  ).auth.signOut({ scope: "local" });
  if (error)
    return { message: "로그아웃하지 못했어요. 잠시 후 다시 시도해 주세요." };
  redirect("/auth/login?notice=signed-out");
}

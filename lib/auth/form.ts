export type AuthField = "email" | "password" | "confirmPassword";
export type AuthState = { message?: string; field?: AuthField; success?: boolean };
export type AuthAction = (state: AuthState, data: FormData) => Promise<AuthState>;

export const passwordHint = "12자 이상, UTF-8 기준 72바이트 이하로 입력해 주세요.";

export function readEmail(form: FormData) {
  const value = form.get("email");
  const email = typeof value === "string" ? value.trim().toLowerCase() : "";
  return email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}

export function readPassword(form: FormData) {
  const value = form.get("password");
  return typeof value === "string" ? value : "";
}

export function validateNewPassword(password: string, form: FormData): AuthState | null {
  if (password.length > 72 || new TextEncoder().encode(password).length > 72 || [...password].length < 12) {
    return { field: "password", message: passwordHint };
  }
  if (password !== form.get("confirmPassword")) {
    return { field: "confirmPassword", message: "비밀번호가 일치하지 않아요." };
  }
  return null;
}

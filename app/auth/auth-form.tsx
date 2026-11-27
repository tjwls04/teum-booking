"use client";

import { useActionState, useState } from "react";
import { type AuthAction, type AuthField, type AuthState, passwordHint } from "../../lib/auth/form";

type Mode = "login" | "signup" | "email" | "reset" | "confirm" | "logout";

export function AuthForm({
  action,
  mode,
  submitLabel,
  notification,
}: {
  action: AuthAction;
  mode: Mode;
  submitLabel: string;
  notification?: string;
}) {
  const [state, submit, pending] = useActionState(action, {} as AuthState);
  const [email, setEmail] = useState("");
  const hasEmail = mode === "login" || mode === "signup" || mode === "email";
  const hasNewPassword = mode === "signup" || mode === "reset";

  function fieldError(field: AuthField) {
    return state.field === field ? state.message : undefined;
  }

  return (
    <form action={submit} className="grid gap-5" aria-busy={pending}>
      {mode === "login" && notification && <input type="hidden" name="notification" value={notification} />}
      {hasEmail && (
        <div className="grid gap-2">
          <label htmlFor="auth-email" className="font-semibold">사업자 이메일</label>
          <input
            id="auth-email"
            className="auth-input"
            name="email"
            type="email"
            autoComplete={mode === "login" ? "username" : "email"}
            maxLength={254}
            value={email}
            onChange={(event) => setEmail(event.currentTarget.value)}
            required
            aria-invalid={Boolean(fieldError("email"))}
            aria-describedby={fieldError("email") ? "auth-email-error" : undefined}
          />
          {fieldError("email") && <p id="auth-email-error" className="auth-error" role="alert">{fieldError("email")}</p>}
        </div>
      )}
      {(hasNewPassword || mode === "login") && (
        <div className="grid gap-2">
          <label htmlFor="auth-password" className="font-semibold">{mode === "reset" ? "새 비밀번호" : "비밀번호"}</label>
          <input
            id="auth-password"
            className="auth-input"
            name="password"
            type="password"
            autoComplete={hasNewPassword ? "new-password" : "current-password"}
            maxLength={hasNewPassword ? 72 : 1024}
            required
            aria-invalid={Boolean(fieldError("password"))}
            aria-describedby={fieldError("password") ? "auth-password-error" : hasNewPassword ? "auth-password-hint" : undefined}
          />
          {hasNewPassword && <p id="auth-password-hint" className="text-sm text-muted">{passwordHint}</p>}
          {fieldError("password") && <p id="auth-password-error" className="auth-error" role="alert">{fieldError("password")}</p>}
        </div>
      )}
      {hasNewPassword && (
        <div className="grid gap-2">
          <label htmlFor="auth-confirm-password" className="font-semibold">비밀번호 확인</label>
          <input
            id="auth-confirm-password"
            className="auth-input"
            name="confirmPassword"
            type="password"
            autoComplete="new-password"
            maxLength={72}
            required
            aria-invalid={Boolean(fieldError("confirmPassword"))}
            aria-describedby={fieldError("confirmPassword") ? "auth-confirm-password-error" : undefined}
          />
          {fieldError("confirmPassword") && (
            <p id="auth-confirm-password-error" className="auth-error" role="alert">{fieldError("confirmPassword")}</p>
          )}
        </div>
      )}
      {state.message && !state.field && (
        state.success
          ? <p className="auth-notice" role="status">{state.message}</p>
          : <p className="auth-error" role="alert">{state.message}</p>
      )}
      <button className="auth-button" type="submit" disabled={pending}>
        {pending ? "처리 중…" : submitLabel}
      </button>
    </form>
  );
}

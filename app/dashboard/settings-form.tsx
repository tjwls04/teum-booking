"use client";

import type { ComponentProps, ReactNode } from "react";
import { useActionState, useId, useState } from "react";
import type { SettingsAction, SettingsState } from "../../lib/dashboard/settings";
import styles from "./dashboard.module.css";

const initialState: SettingsState = {};

export function ServiceRequestId({ initial }: { initial: string }) {
  const [value] = useState(initial);
  return <input type="hidden" name="requestId" value={value} />;
}

export function SettingsForm({
  action, submitLabel, children,
}: {
  action: SettingsAction;
  submitLabel: string;
  children: ReactNode;
}) {
  const [state, submit, pending] = useActionState(action, initialState);
  return (
    <form action={submit} className={styles.form} aria-busy={pending} onReset={(event) => event.preventDefault()}>
      {children}
      {state.error && <p className="auth-error" role="alert">{state.error}</p>}
      <div>
        <button className="auth-button" type="submit" disabled={pending}>
          {pending ? "저장 중…" : submitLabel}
        </button>
      </div>
    </form>
  );
}

type FieldProps = Omit<ComponentProps<"input">, "value" | "defaultValue" | "id" | "onChange"> & {
  label: string;
  initial?: string | number;
  hint?: string;
};

export function Field({ label, initial = "", hint, ...props }: FieldProps) {
  const id = useId();
  const [value, setValue] = useState(String(initial));
  return (
    <div className="grid min-w-0 gap-2">
      <label htmlFor={id} className="font-semibold">{label}</label>
      <input {...props} id={id} className="auth-input" value={value}
        onChange={(event) => setValue(event.currentTarget.value)}
        aria-describedby={hint ? `${id}-hint` : undefined}
      />
      {hint && <p id={`${id}-hint`} className="text-sm text-muted">{hint}</p>}
    </div>
  );
}

export function TextField({
  label, name, initial, maxLength = 2000,
}: { label: string; name: string; initial: string; maxLength?: number }) {
  const id = useId();
  const [value, setValue] = useState(initial);
  return (
    <div className="grid min-w-0 gap-2">
      <label htmlFor={id} className="font-semibold">{label}</label>
      <textarea id={id} name={name} className="auth-input" rows={3} maxLength={maxLength}
        value={value} onChange={(event) => setValue(event.currentTarget.value)}
      />
    </div>
  );
}

export function SelectField({
  label, name, initial, options,
}: {
  label: string;
  name: string;
  initial: string;
  options: ReadonlyArray<readonly [string, string]>;
}) {
  const id = useId();
  const [value, setValue] = useState(initial);
  return (
    <div className="grid min-w-0 gap-2">
      <label htmlFor={id} className="font-semibold">{label}</label>
      <select id={id} className="auth-input" name={name} value={value}
        onChange={(event) => setValue(event.currentTarget.value)}>
        {options.map(([key, text]) => <option key={key} value={key}>{text}</option>)}
      </select>
    </div>
  );
}

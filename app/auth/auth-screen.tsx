import type { ReactNode } from "react";

export function AuthScreen({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: ReactNode;
}) {
  return (
    <main className="shell auth-area">
      <div className="auth-screen">
        <h1 className="section-title">{title}</h1>
        {description && <p className="auth-description">{description}</p>}
        <div className="auth-content">{children}</div>
      </div>
    </main>
  );
}

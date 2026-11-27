"use client";

import { type ReactNode, useActionState, useEffect, useState } from "react";
import { registerPush, removeCurrentPush } from "./actions";

export function NotificationControl({
  action, children, label,
}: {
  action: (state: string | null, form: FormData) => Promise<string | null>;
  children: ReactNode;
  label: string;
}) {
  const [error, submit, pending] = useActionState(action, null);
  return (
    <form action={submit} aria-busy={pending}>
      {children}
      <button type="submit" className="text-link" disabled={pending}>{pending ? "저장 중…" : label}</button>
      {error && <p role="alert" className="auth-error">{error}</p>}
    </form>
  );
}

function applicationKey(value: string) {
  return Uint8Array.from(atob(`${value.replace(/-/g, "+").replace(/_/g, "/")}=`), (char) => char.charCodeAt(0));
}

export function PushDeviceControl({ publicKey }: { publicKey: string | null }) {
  const [registration, setRegistration] = useState<ServiceWorkerRegistration>();
  const [support, setSupport] = useState<"checking" | "ready" | "unavailable">("checking");
  const [hasSubscription, setHasSubscription] = useState(false);
  const [busy, setBusy] = useState(false);
  const [feedback, setFeedback] = useState({ error: false, text: "" });

  useEffect(() => {
    let mounted = true;
    async function activate() {
      if (!window.isSecureContext || !("serviceWorker" in navigator) || !("PushManager" in window) || !("Notification" in window)) {
        if (mounted) setSupport("unavailable");
        return;
      }
      try {
        await navigator.serviceWorker.register("/notification-sw.js", { scope: "/dashboard/" });
        const worker = await navigator.serviceWorker.ready;
        const existing = await worker.pushManager.getSubscription();
        if (!mounted) return;
        setRegistration(worker);
        setHasSubscription(Boolean(existing));
        setSupport("ready");
      } catch {
        if (mounted) setSupport("unavailable");
      }
    }
    if (publicKey) void activate();
    return () => { mounted = false; };
  }, [publicKey]);

  async function connect() {
    if (!registration || !publicKey || busy) return;
    setBusy(true);
    setFeedback({ error: false, text: "" });
    try {
      if (await Notification.requestPermission() !== "granted") {
        setFeedback({ error: true, text: "이 기기의 브라우저 또는 시스템 설정에서 알림을 허용해 주세요." });
        return;
      }
      const key = applicationKey(publicKey);
      let subscription = await registration.pushManager.getSubscription();
      if (subscription) {
        const previous = subscription.options.applicationServerKey;
        if (previous && (previous.byteLength !== key.length || new Uint8Array(previous).some((byte, index) => byte !== key[index]))) {
          await subscription.unsubscribe();
          subscription = null;
        }
      }
      subscription ??= await registration.pushManager.subscribe({ applicationServerKey: key, userVisibleOnly: true });
      setHasSubscription(true);
      const { endpoint, keys } = subscription.toJSON();
      const error = await registerPush(endpoint, keys?.p256dh, keys?.auth);
      setFeedback({ error: Boolean(error), text: error ?? "이 기기를 연결했어요." });
    } catch {
      setFeedback({ error: true, text: "이 기기를 연결하지 못했어요. 브라우저 설정을 확인해 주세요." });
    } finally {
      setBusy(false);
    }
  }

  async function disconnect() {
    if (!registration || busy) return;
    setBusy(true);
    setFeedback({ error: false, text: "" });
    try {
      const subscription = await registration.pushManager.getSubscription();
      if (subscription) {
        const error = await removeCurrentPush(subscription.endpoint);
        if (error) {
          setFeedback({ error: true, text: error });
          return;
        }
        await subscription.unsubscribe();
      }
      setHasSubscription(false);
      setFeedback({ error: false, text: "이 기기 연결을 해제했어요." });
    } catch {
      setFeedback({ error: true, text: "이 기기 연결을 해제하지 못했어요. 다시 시도해 주세요." });
    } finally {
      setBusy(false);
    }
  }

  if (!publicKey) return <p className="text-sm text-muted">서버의 푸시 설정이 아직 준비되지 않았어요.</p>;
  if (support === "unavailable") {
    return <p className="text-sm text-muted">이 환경에서 푸시를 사용할 수 없어요. iPhone·iPad는 홈 화면에 추가한 앱에서 열어 주세요.</p>;
  }

  return (
    <div className="grid gap-2">
      <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
        <button className="auth-button" type="button" disabled={busy || !registration} onClick={connect}>
          {support === "checking" ? "기기 확인 중…" : "이 기기 연결"}
        </button>
        {hasSubscription && (
          <button className="text-link" type="button" disabled={busy} onClick={disconnect}>이 기기 연결 해제</button>
        )}
      </div>
      {feedback.text && <p className={feedback.error ? "auth-error" : "auth-notice"} role={feedback.error ? "alert" : "status"}>{feedback.text}</p>}
    </div>
  );
}

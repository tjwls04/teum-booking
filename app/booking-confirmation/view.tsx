"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { bookingRequest } from "../../lib/booking/client";
import { type Confirmation, seoulDateTime, validToken, won } from "../../lib/booking/types";
import styles from "../book/booking.module.css";

const statusLabels = {
  pending_deposit: "예약금 입금 대기",
  confirmed: "예약 확정",
  completed: "이용 완료",
  no_show: "미방문",
  cancelled: "예약 취소",
  expired: "예약 만료",
};

export function ConfirmationView() {
  const [booking, setBooking] = useState<Confirmation>();
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(true);
  const [copied, setCopied] = useState(false);
  const [duePassed, setDuePassed] = useState(false);
  const inFlight = useRef<{ token: string } | null>(null);

  const load = useCallback(async (report = false) => {
    const token = window.location.hash.slice(1);
    if (!validToken(token)) {
      inFlight.current = null;
      setMessage("예약을 확인하려면 발급받은 예약 확인 링크를 열어 주세요.");
      setBusy(false);
      return;
    }
    if (inFlight.current?.token === token) return;
    const request = { token };
    inFlight.current = request;
    setBusy(true);
    setMessage("");
    const result = await bookingRequest<Confirmation>(report ? "report" : "confirm", {}, token);
    if (inFlight.current !== request || window.location.hash.slice(1) !== token) return;
    if (result.ok) {
      setBooking(result.data);
      setDuePassed(Boolean(result.data.dueAt && Date.parse(result.data.dueAt) <= Date.now()));
    } else {
      setMessage(result.message);
    }
    inFlight.current = null;
    setBusy(false);
  }, []);

  useEffect(() => {
    void load();
    function onLinkChange() {
      inFlight.current = null;
      setBooking(undefined);
      setCopied(false);
      void load();
    }
    window.addEventListener("hashchange", onLinkChange);
    return () => window.removeEventListener("hashchange", onLinkChange);
  }, [load]);

  useEffect(() => {
    if (!booking?.account || !booking.dueAt || duePassed) return;
    const ms = Math.max(0, Date.parse(booking.dueAt) - Date.now());
    const timer = window.setTimeout(() => {
      setDuePassed(true);
      void load();
    }, ms);
    return () => window.clearTimeout(timer);
  }, [booking, duePassed, load]);

  const reported = booking?.status === "pending_deposit" && booking.depositStatus === "reported";
  const canReport = booking?.canReport ?? (booking?.depositStatus === "awaiting_transfer" && booking.followup === "none"
    && ["pending_deposit", "expired", "cancelled"].includes(booking.status));
  const currentLabel = reported ? "사업자 입금 확인 대기" : booking ? statusLabels[booking.status] : "예약 확인";

  return (
    <main className={`shell ${styles.main}`}>
      <div className={styles.content} aria-busy={busy}>
        <header className={styles.header}>
          <h1 className="section-title">{currentLabel}</h1>
        </header>
        {booking && (
          <>
            <dl className={styles.details}>
              <div><dt>샵</dt><dd>{booking.shopName}</dd></div>
              <div><dt>시술</dt><dd>{booking.serviceName}</dd></div>
              <div><dt>방문</dt><dd>{seoulDateTime(booking.startsAt)}</dd></div>
              <div><dt>전화번호</dt><dd>끝 {booking.phoneLast4}자리</dd></div>
              <div><dt>총 금액</dt><dd>{won(booking.price)}</dd></div>
              {booking.deposit > 0 && <div><dt>예약금</dt><dd>{won(booking.deposit)}</dd></div>}
            </dl>
            {booking.account && !duePassed && (
              <section className={styles.content}>
                <h2 className="font-bold text-pine">입금 안내</h2>
                <dl className={styles.details}>
                  <div><dt>계좌</dt><dd>{booking.account.bank} {booking.account.number}</dd></div>
                  <div><dt>예금주</dt><dd>{booking.account.holder}</dd></div>
                  {booking.dueAt && <div><dt>신고 기한</dt><dd>{seoulDateTime(booking.dueAt)}</dd></div>}
                </dl>
                <p>이체 후 기한 안에 이체 사실을 알려 주세요. 사업자의 확인 후 예약이 확정됩니다.</p>
              </section>
            )}
            {booking.account && duePassed && <p>입금 안내 기한이 지났어요. 예약 상태를 다시 확인해 주세요.</p>}
            {reported && <p>이체 신고가 접수됐어요. 사업자가 확인할 때까지 방문 시간은 유지됩니다.</p>}
            {booking.status === "expired" && (
              <p>신고 기한이 지나 방문 시간은 해제됐어요.{canReport && " 이미 이체했다면 아래에서 이체 사실을 알려 주세요."}</p>
            )}
            {booking.followup === "review_needed" && <p>별도 확인이 필요한 이체 기록을 남겼어요. 예약 상태와 방문 시간은 바뀌지 않습니다.</p>}
            {canReport && (
              <button className="auth-button" type="button" disabled={busy} onClick={() => void load(true)}>
                {busy ? "처리 중…" : "이체 사실 알리기"}
              </button>
            )}
            {booking.deposit > 0 && booking.depositPolicy && <p className="whitespace-pre-wrap text-muted">{booking.depositPolicy}</p>}
            {booking.cancellationPolicy && <p className="whitespace-pre-wrap text-muted">{booking.cancellationPolicy}</p>}
            <p className="text-sm text-muted">예약 상태를 다시 보려면 이 링크를 보관하세요. 링크를 받은 사람도 예약 정보를 볼 수 있어요.</p>
            <button type="button" className="text-link" onClick={async () => {
              try {
                await navigator.clipboard.writeText(window.location.href);
                setCopied(true);
              } catch {
                setMessage("주소창에서 이 페이지의 링크를 직접 복사해 주세요.");
              }
            }}>{copied ? "예약 링크를 복사했어요" : "예약 링크 복사"}</button>
          </>
        )}
        {busy && !booking && <p role="status">예약 정보를 확인하는 중이에요.</p>}
        {message && <p className="auth-error" role="alert">{message}</p>}
        {(!busy && (booking || message)) && (
          <button type="button" className="text-link" onClick={() => void load()}>예약 상태 다시 확인</button>
        )}
      </div>
    </main>
  );
}

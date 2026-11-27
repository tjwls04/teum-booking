"use client";

import { type FormEvent, useEffect, useRef, useState } from "react";
import { bookingRequest } from "../../../lib/booking/client";
import { type BookingRequest, type Catalog, consentVersion, seoulClock, validToken, won } from "../../../lib/booking/types";
import styles from "../booking.module.css";

type Envelope = { token: string; booking: BookingRequest };
type Times = { key: string; value: string[]; error?: string };
const failed = "예약 결과를 아직 확인하지 못했어요. 같은 요청으로 다시 확인해 주세요.";

function newToken() {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function BookingForm({ slug }: { slug: string }) {
  const storageKey = `teum-r5-pending:${slug}`;
  const [catalog, setCatalog] = useState<Catalog>();
  const [catalogError, setCatalogError] = useState("");
  const [catalogRequest, refreshCatalog] = useState({ slug });
  const [slotVersion, refreshSlots] = useState(0);
  const [serviceId, setService] = useState("");
  const [day, setDay] = useState("");
  const [start, setStart] = useState("");
  const [customerName, setCustomerName] = useState("");
  const [customerPhone, setCustomerPhone] = useState("");
  const [times, setTimes] = useState<Times>();
  const [pending, setPending] = useState<Envelope>();
  const [localReady, setLocalReady] = useState(false);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const submitting = useRef(false);

  useEffect(() => {
    try {
      const raw = sessionStorage.getItem(storageKey);
      if (raw) {
        const stored: Envelope = JSON.parse(raw);
        if (!validToken(stored?.token) || stored.booking?.slug !== slug || typeof stored.booking.key !== "string") {
          setMessage("저장된 이전 요청을 복구할 수 없어요. 같은 예약을 다시 만들기 전에 결과를 확인해 주세요.");
          return;
        }
        setPending(stored);
        setCustomerName(stored.booking.name);
        setCustomerPhone(stored.booking.phone);
      }
      setLocalReady(true);
    } catch {
      setMessage("이 브라우저에서 예약 복구 정보를 저장할 수 없어요.");
    }
  }, [slug, storageKey]);

  useEffect(() => {
    let current = true;
    bookingRequest<Catalog>("catalog", catalogRequest).then((result) => {
      if (!current) return;
      if (result.ok) {
        setCatalog(result.data);
        setCatalogError("");
        setDay((value) => value >= result.data.today && value <= result.data.lastDay ? value : result.data.today);
        setService((value) => result.data.services.some((item) => item.id === value) ? value : result.data.services[0]?.id ?? "");
      } else {
        setCatalogError(result.message);
      }
    });
    return () => { current = false; };
  }, [catalogRequest]);

  const service = catalog?.services.find((item) => item.id === serviceId);
  const revision = service?.revision;
  const policy = catalog?.policyRevision;
  const slotKey = `${serviceId}:${day}:${revision}:${policy}:${slotVersion}`;
  useEffect(() => {
    if (!serviceId || !day || !revision || !policy) return;
    let current = true;
    bookingRequest<string[]>("slots", { slug, service: serviceId, day, revision, policy }).then((result) => {
      if (!current) return;
      setTimes(result.ok
        ? { key: slotKey, value: result.data }
        : { key: slotKey, value: [], error: result.message });
    });
    return () => { current = false; };
  }, [slug, serviceId, day, revision, policy, slotKey]);

  async function transmit(envelope: Envelope) {
    if (submitting.current) return;
    submitting.current = true;
    setBusy(true);
    setMessage("");
    const result = await bookingRequest<{ created: boolean }>("create", envelope.booking, envelope.token);
    if (result.ok) {
      try { sessionStorage.removeItem(storageKey); } catch {}
      window.location.replace(`/booking-confirmation#${envelope.token}`);
      return;
    }

    // These DB checks happen after successful idempotency lookup under the shop lock.
    if (["r5_revision", "r5_time"].includes(result.code)) {
      try {
        sessionStorage.removeItem(storageKey);
        setPending(undefined);
        setStart("");
        refreshCatalog({ slug });
        refreshSlots((value) => value + 1);
        setMessage(result.message);
      } catch {
        setMessage(failed);
      }
    } else {
      setMessage(result.code === "unavailable" || result.code === "r5_missing" ? failed : result.message);
    }
    submitting.current = false;
    setBusy(false);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submitting.current || pending || !service || !policy || !localReady || !validTimes?.value.includes(start)) return;

    const form = new FormData(event.currentTarget);
    if (form.get("consent") !== "yes") return;
    const name = String(form.get("name") ?? "").trim();
    const phone = String(form.get("phone") ?? "").replace(/[ -]/g, "");
    if (!name || /[\p{Cc}]/u.test(name) || !/^01[016789][0-9]{7,8}$/.test(phone)) {
      setMessage("이름과 휴대전화 번호를 확인해 주세요.");
      return;
    }
    try {
      const envelope = {
        token: newToken(),
        booking: { slug, service: service.id, start, revision: service.revision, policy, name, phone, consent: consentVersion, key: crypto.randomUUID() },
      };
      sessionStorage.setItem(storageKey, JSON.stringify(envelope));
      setPending(envelope);
      await transmit(envelope);
    } catch {
      setMessage("예약 복구 정보를 저장할 수 없어 요청을 보내지 못했어요.");
    }
  }

  const validTimes = times?.key === slotKey ? times : undefined;
  return (
    <main className={`shell ${styles.main}`}>
      <div className={styles.content}>
        <header className={styles.header}>
          <h1 className="section-title">{catalog?.name ?? "고객 예약"}</h1>
          {catalog && <p className="auth-description">시술과 방문 시간을 선택해 주세요.</p>}
        </header>
        {pending ? (
          <section className={styles.section} aria-busy={busy}>
            <h2 className="font-bold text-pine">이전 예약 요청 확인</h2>
            <p className="text-muted">선택한 시간은 {seoulClock(pending.booking.start)}입니다. 같은 요청으로 예약 결과를 확인합니다.</p>
            {message && <p className="auth-error" role="alert">{message}</p>}
            <button className="auth-button" type="button" disabled={busy} onClick={() => void transmit(pending)}>
              {busy ? "확인 중…" : "같은 요청 다시 확인"}
            </button>
          </section>
        ) : (
          <>
            {catalogError && (
              <div>
                <p className="auth-error" role="alert">{catalogError}</p>
                <button type="button" className="text-link" onClick={() => refreshCatalog({ slug })}>샵 정보 다시 불러오기</button>
              </div>
            )}
            {!catalog && !catalogError && <p role="status">샵 정보를 불러오는 중이에요.</p>}
            {catalog && !catalog.services.length && <p>현재 예약할 수 있는 시술이 없어요.</p>}
            {catalog && service && (
              <form onSubmit={submit} className={styles.content}>
                <fieldset className={styles.section}>
                  <legend>시술</legend>
                  <label className="grid gap-2">
                    시술 선택
                    <select className="auth-input" value={serviceId} onChange={(event) => { setService(event.currentTarget.value); setStart(""); }}>
                      {catalog.services.map((item) => <option key={item.id} value={item.id}>{item.name} · {won(item.price)}</option>)}
                    </select>
                  </label>
                  {service.description && <p className="whitespace-pre-wrap text-muted">{service.description}</p>}
                  <p className="text-sm text-muted">시술 {service.duration}분 · 준비 {service.buffer}분</p>
                </fieldset>
                <fieldset className={styles.section}>
                  <legend>방문 날짜와 시간</legend>
                  <label className="grid gap-2">
                    날짜 (서울 시간)
                    <input className="auth-input" type="date" value={day} min={catalog.today} max={catalog.lastDay}
                      required onChange={(event) => { setDay(event.currentTarget.value); setStart(""); }} />
                  </label>
                  {day && !validTimes && <p role="status">가능한 시간을 불러오는 중이에요.</p>}
                  {validTimes?.error && (
                    <>
                      <p className="auth-error" role="alert">{validTimes.error}</p>
                      <button type="button" className="text-link" onClick={() => {
                        setStart("");
                        refreshCatalog({ slug });
                        refreshSlots((value) => value + 1);
                      }}>예약 조건 다시 불러오기</button>
                    </>
                  )}
                  {validTimes && !validTimes.error && !validTimes.value.length && <p>이 날짜에 예약 가능한 시간이 없어요.</p>}
                  <div className={styles.times}>
                    {validTimes?.value.map((time) => (
                      <button className={styles.time} type="button" key={time} aria-pressed={start === time} onClick={() => setStart(time)}>
                        {seoulClock(time)}
                      </button>
                    ))}
                  </div>
                </fieldset>
                <fieldset className={styles.section}>
                  <legend>예약 조건</legend>
                  <p>총 {won(service.price)} · 예약금 {won(service.deposit)}</p>
                  {service.deposit > 0 && (
                    <>
                      <p>예약금 이체 후 잔액은 {won(service.price - service.deposit)}입니다. 예약 신청 후 최대 {catalog.reportMinutes}분 이내이며 방문 시작 전에 이체 사실을 알려야 해요. 사업자가 입금을 확인하면 예약이 확정됩니다.</p>
                      <p className="whitespace-pre-wrap text-muted">{catalog.depositPolicy}</p>
                    </>
                  )}
                  <p className="text-muted">{catalog.cancellationMinutes === 0 ? "예약 시작 전까지 취소 가능" : `예약 시작 ${catalog.cancellationMinutes}분 전까지 취소 가능`}</p>
                  {catalog.cancellationPolicy && <p className="whitespace-pre-wrap text-muted">{catalog.cancellationPolicy}</p>}
                </fieldset>
                <fieldset className={styles.section}>
                  <legend>예약자 정보</legend>
                  <label className="grid gap-2">이름<input className="auth-input" name="name" autoComplete="name"
                    maxLength={60} value={customerName} onChange={(event) => setCustomerName(event.currentTarget.value)} required /></label>
                  <label className="grid gap-2">휴대전화 번호<input className="auth-input" name="phone" type="tel" autoComplete="tel-national"
                    maxLength={20} value={customerPhone} onChange={(event) => setCustomerPhone(event.currentTarget.value)} required /></label>
                  <label className={styles.choice}>
                    <input type="checkbox" name="consent" value="yes" required />
                    <span>예약 조건을 확인했으며, 예약 처리 및 문의 대응을 위한 이름·휴대전화 번호 수집과 이용에 동의합니다. (필수)</span>
                  </label>
                </fieldset>
                <button className="auth-button" type="submit" disabled={!localReady || !validTimes?.value.includes(start)}>
                  {service.deposit > 0 ? "예약 신청하기" : "예약하기"}
                </button>
              </form>
            )}
            {message && <p className="auth-error" role="alert">{message}</p>}
          </>
        )}
      </div>
    </main>
  );
}

"use client";

import { useRef, useState } from "react";
import { type Period, toClock, weekdays } from "../../../lib/dashboard/settings";
import { saveHours } from "../actions";
import styles from "../dashboard.module.css";
import { SettingsForm } from "../settings-form";

type Row = { id: number; day: number; kind: Period["period_kind"]; start: string; end: string };
const kindLabels = { opening: "영업", break: "휴식" } as const;

export function HoursEditor({ shopId, revision, periods }: { shopId: string; revision: number; periods: Period[] }) {
  const [rows, setRows] = useState<Row[]>(() => periods.map((period, index) => ({
    id: index, day: period.iso_weekday, kind: period.period_kind,
    start: toClock(period.start_minute), end: toClock(period.end_minute),
  })));
  const nextId = useRef(periods.length);

  function add(day: number, kind: Row["kind"]) {
    const id = nextId.current++;
    setRows((previous) => [...previous, {
      id, day, kind, start: kind === "opening" ? "09:00" : "12:00", end: kind === "opening" ? "18:00" : "13:00",
    }]);
  }

  function update(id: number, field: "start" | "end", value: string) {
    setRows((previous) => previous.map((row) => row.id === id ? { ...row, [field]: value } : row));
  }

  return (
    <SettingsForm action={saveHours} submitLabel="영업시간 저장">
      <input type="hidden" name="shop" value={shopId} />
      <input type="hidden" name="revision" value={revision} />
      <input type="hidden" name="periods" value={JSON.stringify(rows)} />
      {weekdays.map((label, index) => {
        const day = index + 1;
        const dayRows = rows.filter((row) => row.day === day);
        const open = dayRows.some((row) => row.kind === "opening");
        return (
          <fieldset key={label} className={styles.group}>
            <legend>{label}</legend>
            {dayRows.length === 0 && <p className="text-sm text-muted">휴무</p>}
            {dayRows.map((row) => (
              <div key={row.id} className={styles.period}>
                <p className={styles.periodKind}>{kindLabels[row.kind]}</p>
                {(["start", "end"] as const).map((field) => {
                  const inputId = `period-${row.id}-${field}`;
                  const timeLabel = field === "start" ? "시작" : "종료";
                  return (
                    <div className="grid min-w-0 gap-1" key={field}>
                      <label htmlFor={inputId} className="text-sm">{timeLabel}</label>
                      <input id={inputId} className="auth-input" type="text" maxLength={5}
                        autoComplete="off" placeholder="00:00" required
                        aria-label={`${label} ${kindLabels[row.kind]} ${timeLabel}`}
                        value={row[field]}
                        onChange={(event) => update(row.id, field, event.currentTarget.value)}
                      />
                    </div>
                  );
                })}
                <button className="text-link" type="button"
                  aria-label={`${label} ${kindLabels[row.kind]} ${row.start} 구간 삭제`}
                  onClick={() => setRows((previous) => previous.filter((item) => item.id !== row.id))}>
                  삭제
                </button>
              </div>
            ))}
            <div className={styles.controls}>
              <button className="text-link" type="button" disabled={rows.length >= 96}
                onClick={() => add(day, "opening")}>영업시간 추가</button>
              {open && <button className="text-link" type="button" disabled={rows.length >= 96}
                onClick={() => add(day, "break")}>휴식 추가</button>}
              {dayRows.length > 0 && <button className="text-link" type="button"
                onClick={() => setRows((previous) => previous.filter((row) => row.day !== day))}>휴무로 설정</button>}
            </div>
          </fieldset>
        );
      })}
    </SettingsForm>
  );
}

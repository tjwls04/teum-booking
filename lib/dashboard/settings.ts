export const maxBookingWindowDays = 90;

export type SettingsState = { error?: string };
export type SettingsAction = (state: SettingsState, form: FormData) => Promise<SettingsState>;

export type Period = {
  iso_weekday: number;
  period_kind: "opening" | "break";
  start_minute: number;
  end_minute: number;
};

export const weekdays = ["월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일"];

export function isUuid(value: string) {
  return /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(value);
}

export function toClock(minute: number) {
  return `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
}

export function clockMinute(value: unknown) {
  if (typeof value !== "string" || !/^[0-9]{2}:(00|15|30|45)$/.test(value)) return null;
  const [hours, minutes] = value.split(":").map(Number);
  const total = hours * 60 + minutes;
  return total <= 1440 ? total : null;
}

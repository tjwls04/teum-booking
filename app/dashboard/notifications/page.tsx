import Link from "next/link";
import { seoulDateTime } from "../../../lib/booking/types";
import { requireShop } from "../../../lib/dashboard/server";
import { isUuid } from "../../../lib/dashboard/settings";
import { vapidConfig } from "../../../lib/notifications/push";
import { type InboxItem, notificationLabels, notificationTarget, type PushPreferences } from "../../../lib/notifications/types";
import { Heading } from "../section";
import { removePushDevice, setPushEnabled, updateRead } from "./actions";
import { NotificationControl, PushDeviceControl } from "./control";
import styles from "./notifications.module.css";

const base = "/dashboard/notifications";

export default async function NotificationsPage({ searchParams }: PageProps<"/dashboard/notifications">) {
  const { supabase, shop } = await requireShop();
  const { filter, before, id } = await searchParams;
  const unread = filter === "unread";
  const cursor = typeof before === "string" && /^\d{4}-\d{2}-\d{2}T[\d:.]+(?:Z|[+-]\d\d:\d\d)$/.test(before)
    && Number.isFinite(Date.parse(before)) && typeof id === "string" && isUuid(id) ? { before, id } : null;
  const [inbox, preferences] = await Promise.all([
    supabase.rpc("r8_inbox", { p_shop: shop.id, p_unread: unread, p_before: cursor?.before ?? null, p_before_id: cursor?.id ?? null }),
    supabase.rpc("r8_preferences", { p_shop: shop.id }),
  ]);
  const items = (inbox.data ?? []) as InboxItem[];
  const settings = preferences.data as PushPreferences | null;
  const last = items[29];
  const firstPage = unread ? `${base}?filter=unread` : base;

  return (
    <>
      <Heading title="알림" description="예약과 입금 관련 소식을 확인하세요." />
      <nav className={styles.toolbar} aria-label="알림 필터">
        <Link prefetch={false} href={base} className="text-link" aria-current={!unread ? "page" : undefined}>전체</Link>
        <Link prefetch={false} href={`${base}?filter=unread`} className="text-link" aria-current={unread ? "page" : undefined}>안 읽음</Link>
        <NotificationControl action={updateRead} label="모두 읽음으로">
          <input type="hidden" name="id" value="all" />
          <input type="hidden" name="read" value="yes" />
        </NotificationControl>
      </nav>
      {inbox.error ? <p role="alert" className="auth-error">알림을 불러오지 못했어요. 새로고침해 주세요.</p> :
        items.length === 0 ? <p className="py-4 text-muted">{unread ? "안 읽은 알림이 없어요." : "도착한 알림이 없어요."}</p> : (
          <ul className={styles.rows}>
            {items.slice(0, 30).map((item) => (
              <li className={styles.row} key={item.id}>
                <div>
                  <Link prefetch={false} href={notificationTarget(item)} className={`text-link ${item.read_at ? "" : "font-semibold"}`}>
                    {notificationLabels[item.kind]}
                  </Link>
                  <p className="text-sm text-muted"><time dateTime={item.created_at}>{seoulDateTime(item.created_at)}</time> · {item.read_at ? "읽음" : "안 읽음"}</p>
                </div>
                <NotificationControl action={updateRead} label={item.read_at ? "안 읽음으로" : "읽음으로"}>
                  <input type="hidden" name="id" value={item.id} />
                  <input type="hidden" name="read" value={item.read_at ? "no" : "yes"} />
                </NotificationControl>
              </li>
            ))}
          </ul>
        )}
      {!inbox.error && (cursor || (items.length > 30 && last)) && (
        <nav className={styles.toolbar} aria-label="알림 목록 페이지">
          {cursor && <Link prefetch={false} className="text-link" href={firstPage}>처음으로</Link>}
          {items.length > 30 && last && <Link prefetch={false} className="text-link"
            href={`${base}?${new URLSearchParams({ filter: unread ? "unread" : "all", before: last.created_at, id: last.id })}`}>이전 알림 보기</Link>}
        </nav>
      )}
      <section className={styles.section} aria-labelledby="push-heading">
        <div>
          <h2 id="push-heading" className="text-lg font-semibold text-pine">기기 푸시 알림</h2>
          <p className="text-sm text-muted">휴대폰이나 브라우저에서도 알림을 받을 수 있어요. 푸시를 꺼도 이 목록에는 알림이 계속 쌓여요.</p>
        </div>
        {preferences.error || !settings ? <p role="alert" className="auth-error">푸시 설정을 불러오지 못했어요.</p> : (
          <>
            <div className={styles.toolbar}>
              <p>모든 연결 기기에서 푸시 {settings.enabled ? "켜짐" : "꺼짐"}</p>
              <NotificationControl action={setPushEnabled} label={settings.enabled ? "푸시 끄기" : "푸시 켜기"}>
                <input type="hidden" name="enabled" value={settings.enabled ? "no" : "yes"} />
              </NotificationControl>
            </div>
            <PushDeviceControl publicKey={vapidConfig()?.publicKey ?? null} />
            <h3 className="font-semibold text-pine">연결된 기기 {settings.devices.length}대</h3>
            {settings.devices.length > 0 && (
              <ul className={styles.rows}>
                {settings.devices.map((device) => (
                  <li className={styles.row} key={device.id}>
                    <p className="text-sm text-muted"><time dateTime={device.created_at}>{seoulDateTime(device.created_at)}</time>에 연결</p>
                    <NotificationControl action={removePushDevice} label="이 연결 해제">
                      <input type="hidden" name="id" value={device.id} />
                    </NotificationControl>
                  </li>
                ))}
              </ul>
            )}
          </>
        )}
      </section>
    </>
  );
}

/* global clients */
const messages = {
  created: "새 예약이 들어왔어요.",
  deposit_reported: "고객이 입금을 신고했어요.",
  expired: "입금 기한이 지나 예약이 만료됐어요.",
  deposit_reported_late: "기한이 지난 입금 신고를 확인해 주세요.",
  deposit_delayed: "입금 확인이 필요한 예약이 있어요.",
  today: "오늘 예정된 예약을 확인해 주세요.",
};

function openPath(id) {
  return typeof id === "string" && /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(id)
    ? `/dashboard/notifications/open/${id}`
    : "/dashboard/notifications";
}

self.addEventListener("install", (event) => event.waitUntil(self.skipWaiting()));
self.addEventListener("activate", (event) => event.waitUntil(clients.claim()));

self.addEventListener("push", (event) => {
  let data;
  try {
    data = event.data?.json();
  } catch {
    data = null;
  }
  const { id, kind } = data ?? {};
  event.waitUntil(self.registration.showNotification("틈예약", {
    body: Object.hasOwn(messages, kind) ? messages[kind] : "대시보드에서 알림을 확인해 주세요.",
    icon: "/app-icon-192.png",
    tag: openPath(id),
    renotify: false,
    data: { id },
  }));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = openPath(event.notification.data?.id);
  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: "window", includeUncontrolled: true });
    const existing = windows.find((window) => {
      const path = new URL(window.url).pathname;
      return path === "/dashboard" || path.startsWith("/dashboard/");
    });
    if (existing) {
      const window = await existing.navigate(target).catch(() => null);
      if (window) {
        await window.focus();
        return;
      }
    }
    await clients.openWindow(target);
  })());
});

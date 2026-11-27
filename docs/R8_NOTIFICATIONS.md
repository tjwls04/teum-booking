# R8 사업자 알림 운영 안내

## 알림과 발송 기준

| 알림 | 생성 기준 | 클릭 시 이동 |
| --- | --- | --- |
| 신규 예약 | 온라인 또는 수동 예약 생성 | 예약 상세 |
| 고객 입금 신고 | 고객이 기한 내 입금을 신고 | 예약금 상세 |
| 예약 만료 | 미신고 예약이 실제 만료되어 점유가 해제됨 | 예약 상세 |
| 늦은 입금 신고 | 종료된 예약에 고객이 입금을 신고 | 예약금 상세 |
| 입금 확인 지연 | 신고 기한을 넘겼고 사업자 확인을 기다리는 예약, 예약당 한 번 | 예약금 상세 |
| 당일 예약 안내 | 서울 기준 당일 08시부터 시작 전까지. 오전 9시 전 예약은 당일 시작 1시간 전부터, 예약·날짜당 한 번 | 예약 상세 |

알림 목록은 앱의 읽음 상태와 건수를 공유한다. 푸시 설정은 샵의 전체 기기에 적용하며 앱 내부 알림은 계속 생성된다. 푸시를 다시 켜기 전에 쌓인 알림은 발송 대기열에서 제외된다. 기기는 샵당 10대까지 등록할 수 있다. 공용 기기는 로그아웃하기 전에 대시보드에서 해제한다. 다른 기기에서 등록을 해제하면 서버의 연결 정보가 제거된다. 이미 발송 처리 중이거나 OS에 표시된 알림에는 해제가 소급 적용되지 않는다.

예약 이벤트의 DB 트리거가 알림과 발송 작업을 함께 저장한다. 정기 작업의 안내는 예약 상태를 조회해 별도로 생성한다. 마이그레이션 이전 이벤트는 소급 생성하지 않는다. 푸시에는 알림 종류와 알림 UUID만 담고, 클릭하면 세션과 샵 소유권을 검증한 뒤 상세로 이동한다. 로그인 세션이 없으면 로그인 후 같은 알림을 다시 확인한다.

워커는 당시 등록된 활성 기기마다 한 건의 발송을 준비한다. 발송 시도마다 90초 lease를 부여하며 워커가 종료되면 다음 실행에서 만료된 작업을 회수한다. 네트워크 오류, HTTP 408·425·429 및 5xx는 최대 5회까지 지수 백오프와 `Retry-After`를 적용한다. 404·410은 해당 기기의 구독을 해제한다. 최종 결과는 상태와 제한된 오류 코드로 보관한다. 알림 생성 후 24시간 또는 당일 예약 시작 시각이 지나면 새 발송을 시도하지 않는다. 제공사 응답 전에 워커가 중단되면 기기에서 중복 표시될 수 있다. 푸시 Topic과 알림 tag에 같은 식별자를 사용해 대기 메시지와 기존 표시를 합칠 수 있다.

## 개발 DB와 앱 설정

1. R2~R7 적용을 확인한 뒤 `supabase/migrations/20261127080000_r8_notifications.sql`을 적용한다. SQL Editor에서 수동 적용할 경우 파일 전체를 하나의 트랜잭션으로 실행하고 CLI 마이그레이션 이력을 별도로 관리한다. 개발 DB에서 `supabase/verify/r8_notifications.sql`을 실행해 `R8 notification checks passed`를 확인한다. 테스트 데이터는 롤백된다.
2. 신뢰하는 개발 머신에서 `npx --no-install web-push generate-vapid-keys`로 환경별 키 쌍을 생성해 보안 저장소에 보관한다. Node 앱 서버에 `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, 실제 연락처를 담은 `VAPID_SUBJECT`(`mailto:` 또는 `https:`)를 설정한다. 기존 `SUPABASE_SECRET_KEY`를 워커에도 사용한다. 키 쌍을 교체하면 기존 기기를 다시 연결한다.
3. 별도의 32바이트 난수로 `NOTIFICATION_WORKER_KEY`를 만들어 Node 앱과 Supabase Vault에 같은 값을 저장한다. Vault에 `teum_r8_worker_key`와 앱의 HTTPS origin을 담은 `teum_r8_app_origin`을 등록한다. Supabase 대시보드에서 Cron과 `pg_net`을 활성화한다. R7의 만료 Cron은 기존 설정을 사용한다.
4. 마이그레이션 소유자가 SQL Editor에서 아래 Cron을 등록한다. 개발 Vault origin과 작업 키는 개발 앱과 일치해야 한다. 복제된 환경에서도 작업을 활성화하기 전에 origin과 키를 확인한다. [Supabase Cron 및 Vault 예제](https://supabase.com/docs/guides/functions/schedule-functions) · [Supabase pg_net](https://supabase.com/docs/guides/database/extensions/pg_net)

```sql
select cron.schedule(
  'teum-r8-notification-worker',
  '* * * * *',
  $cron$
    select net.http_post(
      url := rtrim(origin.decrypted_secret, '/') || '/api/internal/notifications',
      headers := jsonb_build_object('Authorization', 'Bearer ' || token.decrypted_secret),
      timeout_milliseconds := 65000
    )
    from vault.decrypted_secrets origin
    cross join vault.decrypted_secrets token
    where origin.name = 'teum_r8_app_origin' and token.name = 'teum_r8_worker_key';
  $cron$
);
```

Cron 실행 이력은 HTTP 작업 등록까지 확인한다. `pg_net` 응답 코드와 DB 소유자 권한에서 본 `r8_private.deliveries`의 `status`, `attempts`, `last_error`로 워커 및 제공사 응답을 확인한다. HTTP 2xx는 제공사 접수 결과다. 마지막으로 허구 예약을 만들어 휴대폰에서 표시와 클릭을 확인한다. 기기 endpoint, 암호화 키, `Authorization` 헤더는 진단 출력에 넣지 않는다.

워커는 Chrome용 FCM, Firefox용 Mozilla Autopush, Safari용 Apple Push의 HTTPS endpoint 패턴만 받는다. 검증한 공개 IPv4 주소에 직접 연결하면서 제공사 TLS 호스트를 확인하며 HTTP 리다이렉트는 따르지 않는다. 호스팅 환경에서 해당 제공사의 DNS와 TCP 443 아웃바운드가 필요하다. [Apple Web Push 전송 요구사항](https://developer.apple.com/documentation/usernotifications/sending-web-push-notifications-in-web-apps-and-browsers)

## 휴대폰 설정

- **iPhone·iPad**는 iOS·iPadOS 16.4 이상에서 HTTPS로 대시보드를 열고 공유 메뉴에서 **홈 화면에 추가**한다. 홈 화면 아이콘으로 실행해 로그인하고 **알림 → 이 기기 연결**을 직접 눌러 권한을 허용한다. 권한을 거부한 경우 시스템 알림 설정에서 다시 허용한다. [WebKit의 iOS·iPadOS Web Push 안내](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)
- **Android Chrome**은 HTTPS에서 대시보드를 연 다음 **알림 → 이 기기 연결**을 눌러 사이트와 시스템 알림 권한을 허용한다. Chrome의 앱 설치 옵션이 표시되면 홈 화면 설치도 가능하다. 수신이 막혔다면 Chrome의 사이트 알림 설정과 Android의 Chrome 앱 알림 권한을 확인한다. [Chrome 팀의 Push API 구독 안내](https://web.dev/articles/push-notifications-subscribing-a-user)
- 물리 기기에서 신규 예약과 고객 입금 신고를 하나씩 발생시킨 뒤 푸시가 표시되는지 확인한다. 앱을 닫은 상태에서 푸시를 눌러 이동을 확인하고, 로그아웃 뒤 같은 경로가 로그인과 소유권 검증을 거치는지 확인한다.

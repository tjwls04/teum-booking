# R9 발표·제한 테스트 배포

## 개발 DB 준비

1. 발표에 사용할 **개발 또는 데모 전용 Supabase 프로젝트**를 확인한다. 새 프로젝트에서는 저장소의 R2, R4~R9 마이그레이션을 파일명 순서대로 적용한다. R8까지 적용된 프로젝트에는 `20261127090000_r9_deploy_hardening.sql`만 적용한다. R9 앱은 새 예약 요청 제한 RPC를 사용하므로 **DB 적용이 앱 배포보다 먼저**다.
2. SQL Editor를 사용하면 마이그레이션 파일 하나를 하나의 트랜잭션으로 실행한다. R9는 90일을 넘는 기존 샵 설정을 90일로 제한하고 해당 샵의 정책 revision을 올린다. 기존에 생성된 예약은 유지된다. [R9 마이그레이션](../supabase/migrations/20261127090000_r9_deploy_hardening.sql)
3. 격리된 개발 DB에서 `supabase/verify/`의 R2, R4~R9 검증 SQL을 파일별로 실행한다. 검증 데이터는 롤백된다. R3 인증의 SMTP와 실제 메일 확인은 HTTPS 앱 연결 후에 한다. [R9 검증 SQL](../supabase/verify/r9_deploy_hardening.sql)
4. SQL Editor에서 직접 적용한 변경은 CLI 이력에 자동 기록되지 않는다. 데모 프로젝트 ref를 확인해 CLI를 연결한 뒤 `supabase migration list`의 Local/Remote와 실제 스키마를 대조한다. 본문이 실제로 적용된 로컬 파일의 버전만 `supabase migration repair <버전> --status applied`로 기록한 뒤 다시 조회한다. R3는 SQL 파일이 없으므로 별도 버전을 만들지 않는다. 이력·스키마 차이가 남으면 `db push` 전에 확인한다. [Supabase CLI 마이그레이션 이력](https://supabase.com/docs/reference/cli/supabase-migration-repair)

## Render Web Service

- 승인된 소스 저장소에서 Node Web Service를 만들고 데모 브랜치와 저장소 루트를 선택한다. Node는 `.nvmrc`의 24.22.3을 사용한다. Build Command는 `npm ci && npm run build`, Start Command는 `npm run start -- --hostname 0.0.0.0 --port "$PORT"`다. Health Check Path는 `/api/health`다. 이 경로는 Node 응답 여부를 확인하므로 Auth·DB·푸시 연결은 별도 흐름으로 확인한다. [Render Next.js 배포](https://render.com/docs/deploy-nextjs-app) · [Node 버전 선택](https://render.com/docs/node-version) · [Health Checks](https://render.com/docs/health-checks)
- 빌드 전에 같은 데모 프로젝트의 `NEXT_PUBLIC_SUPABASE_URL`과 `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`를 설정한다. 서버에 `SUPABASE_SECRET_KEY`를 올리고 `BOOKING_APP_ORIGIN`은 브라우저가 사용할 최종 HTTPS origin으로 지정한다. 비밀값은 Render의 환경변수와 승인된 비밀 저장소에서 관리한다. `NEXT_PUBLIC_*` 값이 바뀌면 재빌드한다. [환경변수 예시](../.env.example)
- Render에서 `BOOKING_TRUSTED_IP_HEADER=CF-Connecting-IP`를 사용한다. 사용자 요청이 보낸 동명의 헤더를 실제 ingress가 덮어쓰는지 데모 URL에서 확인한 다음 고객 링크를 공유한다. 사용자 제공 값을 포함할 수 있는 `X-Forwarded-For` 목록은 이 설정에 사용하지 않는다. 검증된 IP가 없으면 앱은 샵별·전체 제한을 적용한다. [Render의 프록시 헤더 안내](https://render.com/articles/host-pocketbase-on-render)
- 데모 프로젝트 Auth의 **Site URL**을 HTTPS origin으로 변경한다. 이메일 확인을 활성화하고 SMTP와 신규 가입·재설정 템플릿을 점검한다. `/auth/email-link`의 fragment 템플릿으로 새 메일을 발행한다. 화면 공유·접근 로그·에러 추적에서 콜백 쿼리, 요청 본문, 쿠키, Authorization을 제외한다. [이메일 템플릿](R3_AUTH.md) · [Supabase Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
- 푸시를 확인할 때 Node 앱에 데모 환경 VAPID 키와 워커 키를 설정한다. Vault에 같은 워커 키와 최종 HTTPS origin을 넣고 R7 만료 Cron과 R8 알림 Cron을 등록한다. 로그에서는 상태 코드와 작업 결과만 조회한다. [R8 운영 안내](R8_NOTIFICATIONS.md)

## 배포 직후 확인

1. HTTPS URL, 정적 홈, `/api/health`의 200 응답을 확인한다. 인증 메일을 새로 발행해 링크가 현재 HTTPS 주소로 열리고 인증·로그인·초기 샵 등록·비밀번호 재설정이 되는지 확인한다.
2. 사업자 두 계정과 합성 예약으로 공개 링크, 시술·영업시간·90일 범위, 고객 예약 및 재시도, 이체 신고, 확인·변경·취소·수동 환불 기록, 다른 샵 접근 차단을 확인한다. 로그아웃 뒤 브라우저 뒤로 가기와 상세 주소 직접 접속도 확인한다.
3. 개발 DB Cron에서 만료·워커 실행을 확인한 뒤 iPhone과 Android에서 푸시 수신·클릭을 확인한다. 발표용 계좌와 고객 정보는 모두 합성 데이터로 준비한다. 데모 중 장애가 발생하면 먼저 직전 호환 앱 빌드로 복귀한다. 데이터베이스 이력과 스키마는 보존하고, 필요한 경우 검토된 후속 마이그레이션으로 수정한다.

## 제한 사용자 테스트에서 확인할 운영 항목

- IP·샵·전체 제한은 한 주소의 반복 요청과 다른 샵으로의 영향을 줄인다. 공개 무가입 예약은 고객 전화번호 소유를 증명하지 않으므로 분산 허위 예약은 남는다. 고객 인증·CAPTCHA·노쇼 정책 결정은 제한 사용자 테스트 결과와 함께 검토한다.
- 부분 입금은 확인한 금액과 사유를 이력으로 남기며 예약을 확정하지 않는다. 여러 건을 실제로 받은 경우 은행에서 합계를 확인하고 입력한다. 환불 기록은 한 건으로 금전 처리를 종료하므로 분할 송금은 외부에서 완료 후 합계를 한 번 기록한다. 다건 수납 원장과 분할 환불 처리 방식은 후속 정책 항목이다.
- 입금 확인 지연 안내는 신고된 예약을 대상으로 하며 점유를 유지한다. 워커는 수신 제공사의 공개 IPv4에 TLS로 연결한다. 실제 제공사 주소 형태·라우팅, 두 휴대폰 플랫폼, 호스팅 Cron 실행은 데모 환경에서 검증한다. 공용 기기는 로그아웃 전에 푸시 구독을 해제한다.

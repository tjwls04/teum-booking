# R2 데이터베이스 적용 및 검증

## 원격 개발 프로젝트 적용 기록

사용자 확인에 따르면 이 프로젝트의 R2 마이그레이션과 검증 SQL은 원격 개발용 Supabase SQL Editor에서 정상 실행됐다. SQL Editor 직접 실행은 CLI의 `supabase_migrations.schema_migrations` 이력을 자동으로 기록하지 않는다. CLI로 관리할 때는 같은 개발 프로젝트의 스키마와 적용 이력을 대조한 뒤, 스키마가 일치하고 버전이 누락된 경우 적용 이력만 별도로 정리한다. [Supabase 마이그레이션 이력](https://supabase.com/docs/guides/deployment/database-migrations)

## 적용 순서

1. Docker 호환 런타임을 시작하고 Supabase CLI와 PostgreSQL 클라이언트(`psql`)를 준비한다. 프로젝트에 Supabase CLI 설정 파일이 없다면 프로젝트 루트에서 `supabase init`을 한 번 실행한다. [Supabase 로컬 개발 안내](https://supabase.com/docs/guides/local-development/cli/getting-started)
2. 프로젝트 루트에서 `supabase start`로 로컬 스택을 시작한다. `supabase migration up`으로 로컬 스택에 미적용 마이그레이션을 적용하고, `supabase migration list`로 로컬 적용 여부를 확인한다. 첫 시작에 자동으로 적용되었다면 추가 적용할 항목이 없다. 원격 대상 옵션은 사용하지 않는다. [마이그레이션](../supabase/migrations/20261127020000_r2_booking_foundation.sql) · [CLI 명령](https://supabase.com/docs/reference/cli/supabase-migration-up)
3. 로컬 관리자 계정으로 아래 명령을 실행한다. 포트를 변경했다면 로컬 포트로 바꾼다. `-W`는 비밀번호를 프롬프트로 받는다. 마지막에 `R2 foundation checks passed`가 표시되어야 한다. 테스트는 가상 사용자·예약을 만들고 전체 롤백한다. 이 파일은 일반 SQL이므로 아래 `psql` 명령으로 실행한다. [검증 SQL](../supabase/verify/r2_booking_foundation.sql)

```sh
psql -X -h 127.0.0.1 -p 54322 -U postgres -d postgres -W \
  -v ON_ERROR_STOP=1 -f supabase/verify/r2_booking_foundation.sql
```

4. 앱에서 로컬 Supabase 클라이언트를 사용할 때 `.env.local`의 기존 `NEXT_PUBLIC_SUPABASE_URL` 및 `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`에 같은 로컬 프로젝트의 URL과 publishable key(`sb_publishable_…`)를 입력한다. Next.js 개발 서버가 실행 중이라면 설정을 다시 읽도록 재시작한다. 이 단계에서 홈페이지에 설정값이나 DB 연결 결과를 추가하지 않았다. [환경변수 예시](../.env.example)

## 데이터 및 권한

- 사업자당 한 샵은 `shops.owner_user_id`의 유일성으로 보장한다. 예약·점유·이벤트의 복합 외래 키는 다른 샵의 기록을 참조할 수 없게 한다.
- 앱의 `anon` 역할은 R2 테이블에 직접 접근할 수 없다. `authenticated`는 영구 로그인 사용자의 소유 샵만 읽을 수 있다. 익명 Auth 세션은 JWT의 `is_anonymous` 조건으로 걸러진다. 예약·이벤트는 필요한 컬럼만 명시해 조회한다. 고객 확인 토큰 해시, 재시도 키, 요청 해시, 예약 당시 계좌 사본 및 이벤트 상세는 직접 조회 권한에서 제외했다. [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
- `service_role`은 RLS를 우회할 수 있어 후속 서버 조회에도 샵 조건이 필요하다. R2 앱 역할에는 직접 쓰기를 허용하지 않는다. 후속 쓰기는 권한을 제한한 RPC로 연결한다.
- 앱의 브라우저·서버 클라이언트는 기존 공개 URL과 publishable key를 사용한다. R3에서 서버 컴포넌트의 쿠키 읽기, Server Action의 쿠키 쓰기와 대시보드 세션 갱신을 연결했다. [R3 인증 안내](R3_AUTH.md) [SSR 클라이언트 안내](https://supabase.com/docs/guides/auth/server-side/creating-a-client?framework=nextjs&queryGroups=framework&router=app)
- 요일별 일정은 ISO 요일과 서울 자정부터의 분으로 저장한다. 자정을 넘는 구간은 날짜별로 나눈다. 실제 예약·차단·기록 시각은 `timestamptz`로 저장하고, 서울 날짜 경계를 계산할 때 `Asia/Seoul`을 명시한다. 같은 요일의 영업·휴식 구간 관계는 R4의 저장·가능 시간 계산에서 검증한다.
- 온라인·수동 예약과 시간 차단은 동일한 15분 점유표를 사용한다. 각 범위의 종료는 제외하므로 종료와 다음 시작이 같을 수 있다. `(shop_id, slot_start)` 기본키가 쓰기 충돌을 차단한다. 전체 슬롯을 채우고 예약·점유·이벤트를 한 트랜잭션에서 기록하며, 취소 시 해당 예약의 슬롯만 삭제하는 로직은 R5에서 구현한다.

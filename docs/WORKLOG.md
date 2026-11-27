# 작업 기록

## 2026-11-27 · R1 로컬 기반 구축

프로젝트 폴더는 `/Users/mac/Desktop/teum-booking-native`다. 시작 시 기획 문서만 있는 폴더였고, 이 경로에 로컬 Git `main` 저장소를 초기화했다. 원격 저장소, push, 외부 배포는 실행하지 않았다.

### 생성 및 수정 파일

- `docs/DESIGN.md`와 `docs/WORKLOG.md`를 추가해 디자인 방향, 색상·서체, 사진 출처, 구현 및 검증 결과를 기록했다.
- `AGENTS.md`, `README.md`, `docs/PROJECT_CONTEXT.md`, `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/USER_FLOW.md`, `docs/DECISIONS.md`, `prompts/01-bootstrap.md`에서 디자인 기준 참조와 R1 진행 상태를 갱신했다. PRD의 제품 요구사항과 기존 예약 규칙은 보존했다.
- `app/layout.tsx`, `app/page.tsx`, `app/globals.css`로 공통 레이아웃, 색상·타이포그래피와 모바일 대응 소개 화면을 구성했다.
- `app/setup/page.tsx`는 로컬 개발 상태와 Supabase 미연결을 안내한다. `app/api/health/route.ts`는 Node.js 런타임 확인용 JSON을 반환한다.
- `app/fonts/PretendardVariable.woff2`, `app/fonts/OFL.txt`, `public/images/salon-chair.jpg`를 앱에 포함했다. 소개 화면은 실제 샵 사진을 사용하며, 구현되지 않은 예약 화면은 표시하지 않는다. [에셋 출처](DESIGN.md#r1-에셋-출처)
- `package.json`, `package-lock.json`, `tsconfig.json`, `postcss.config.mjs`, `biome.json`, `next.config.ts`로 앱 의존성과 실행·빌드·타입·lint를 설정했다. 개발 화면의 Next.js 표시를 숨기고, 패키지에 포함된 문서의 경로를 기존 `AGENTS.md`에 기록했다.
- `.nvmrc`, `.env.example`, `.gitignore`로 검증한 Node 버전, 향후 사용할 공개 설정 이름, 환경변수 및 생성 파일 제외 규칙을 추가했다.

### 환경 및 패키지

- 최초 환경 확인 결과 macOS 26.6.2 arm64, Node.js 24.19.0 LTS, npm 11.17.0, Git 2.54.0(Apple Git-157)이었다. 공식 Node.js 24.22.3 arm64 아카이브를 내려받아 SHA-256을 검증하고 임시 경로에서 npm 11.19.1과 함께 사용했다. 기본 경로의 Node와 npm은 그대로다. [Node.js 릴리스](https://nodejs.org/en/blog/release/v24.22.3) · [Next.js 요구조건](https://nextjs.org/docs/app/getting-started/installation)
- `next@16.4.6`, `react@19.3.1`, `react-dom@19.3.1`은 App Router, React 화면 렌더링과 서버 API에 사용한다.
- `typescript@6.0.3`, `@types/node@24.19.4`, `@types/react@19.3.3`, `@types/react-dom@19.3.0`은 strict 타입 검사에 사용한다. TypeScript 6은 현재 도구의 호환 범위를 사용했다.
- `tailwindcss@4.3.5`, `@tailwindcss/postcss@4.3.5`로 공통 스타일 토큰과 유틸리티를 처리한다.
- `@biomejs/biome@2.6.9`는 개발 도구로만 설치했다. Next.js 권장 규칙과 Tailwind CSS 구문을 검사한다. [Biome Next.js 규칙](https://biomejs.dev/linter/domains/#next)
- Pretendard는 공식 v1.3.9의 로컬 WOFF2를 사용한다. 글꼴 패키지나 별도 UI 라이브러리는 추가하지 않았다.

### 실행 명령 및 결과

- `sw_vers`, `uname -m`, `node -v`, `npm -v`, `git --version`으로 설치 환경을 확인했다. `npm view`로 안정 버전 및 피어 의존성을 확인했다.
- `git status --short --branch`는 처음에 저장소 없음으로 종료했다. `git init -b main`으로 초기화했다. `git remote -v`는 빈 결과였고, `git check-ignore`로 `.env.local`은 제외되고 `.env.example`은 추적 가능한지 확인했다.
- 최종 패키지 구성에서 `npm install`, `npm ci`, `npm ls --depth=0`이 성공했다. 설치 검사에서 알려진 취약점 0건이 표시됐다.
- `npm run typecheck`는 `next typegen`과 strict `tsc --noEmit`에 성공했다.
- `npm run lint`는 최종 실행에서 경고·오류 없이 끝났다.
- `npm run build`는 성공했다. `/`와 `/setup`은 정적 페이지, `/api/health`는 동적 라우트로 생성됐다.
- `npm run dev -- --hostname localhost`로 3000번, `npm start -- --hostname localhost --port 3001`로 3001번에서 실제 실행했다. Supabase 환경변수 없이 두 서버의 `/`, `/setup`, `/api/health`가 모두 HTTP 200을 반환했다. health의 응답 본문은 `{"status":"ok"}`, 형식은 JSON이었고 `Cache-Control: no-store`를 확인했다.
- 설치된 Chrome 159 헤드리스와 DevTools 프로토콜로 320·390·768·1440px에서 가로 넘침이 없고 사진과 글꼴이 로드되는지 확인했다. 소개 섹션 이동, 개발 상태 이동과 새로고침, 홈 복귀를 확인했고 브라우저 런타임 예외는 없었다. 1440px 소개와 390px 소개·개발 상태 화면의 캡처를 확인했다.

### 발견한 오류 및 조정

- 조회한 Fontsource의 Pretendard 패키지 이름이 npm에서 404를 반환했다. 공식 릴리스의 글꼴과 라이선스를 앱에 포함하도록 처리했다.
- ESLint 9 설치에서 지원 종료 경고가 발생했고 설치 시점의 React lint 플러그인은 ESLint 10을 피어 의존성으로 지원하지 않았다. ESLint 관련 항목을 제거하고 Biome으로 전환했다.
- 첫 lint는 CSS 선택자 우선순위 경고 두 건으로 실패했다. 기본 스타일과 상태 규칙 순서를 수정한 뒤 lint를 다시 통과했다.
- 첫 개발 실행에서 Next.js가 기존 `AGENTS.md`에 자동 안내를 붙였고 화면에 개발 표시가 나타났다. 문서 경로 안내를 기존 지침에 반영하고 `next.config.ts`에서 자동 삽입과 화면 표시를 끈 뒤 빌드와 브라우저 검증을 다시 수행했다.

### 로컬 확인 및 남은 범위

- [소개 페이지](http://localhost:3000/)에서 모바일 폭으로 줄인 뒤 ‘서비스 소개’를 눌러 섹션 이동을 확인한다.
- [개발 상태](http://localhost:3000/setup)에서 새로고침 후에도 Supabase 미연결과 사업자 인증·예약 준비 상태가 표시되는지 확인한다.
- [health API](http://localhost:3000/api/health)에서 HTTP 200과 `{"status":"ok"}`를 확인한다.
- R1에서 확인된 미해결 오류는 없다. 물리 휴대폰과 Safari는 확인하지 않았다. 이 단계에는 Supabase, 로그인, 예약, 결제, 알림이 포함되지 않아 연동 테스트를 실행하지 않았다.
- R1 실행에는 외부 계정이나 환경변수가 필요하지 않다. 기본 셸에서 다시 실행할 때는 README의 Node 버전으로 맞춘 뒤 `npm ci`와 `npm run dev`를 실행한다.

## 2026-11-27 · R2 데이터베이스 기반

### 변경 파일

- `supabase/migrations/20261127020000_r2_booking_foundation.sql`에 샵, 시술, 주간 영업·휴식, 계좌, 예약, 차단, 점유, 예약 이벤트 스키마와 RLS·명시적 권한을 추가했다.
- `supabase/verify/r2_booking_foundation.sql`에 허구 데이터로 anon·사업자 A/B·익명 Auth·service_role의 접근과 시간·참조 제약을 확인하는 SQL을 추가했다. 검증 데이터는 롤백한다.
- `lib/supabase/config.ts`, `lib/supabase/client.ts`, `lib/supabase/server.ts`에 기존 공개 환경변수와 설치된 Supabase SSR 클라이언트를 사용하는 설정을 추가했다. 서버는 요청 단위로 생성하고 Route Handler가 전달한 응답에 세션 쿠키와 캐시 헤더를 기록할 수 있다.
- `.env.example`, `.gitignore`, `README.md`, `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, `docs/R2_DATABASE.md`, `docs/WORKLOG.md`를 갱신했다. 홈페이지와 기존 라우트, `.env.local`, 패키지 및 lockfile은 수정하지 않았다.

### 핵심 설계

- 영구 로그인 사업자는 소유 샵만 읽는다. 예약·이벤트는 컬럼 단위 읽기 권한을 주며 anon은 테이블 접근을 차단한다. 앱 역할에 대한 직접 쓰기는 후속 RPC까지 닫아 둔다.
- 예약과 차단은 같은 15분 점유표와 `(shop_id, slot_start)` 기본키를 사용한다. 복합 외래 키는 다른 샵을 참조할 수 없게 한다. ISO 요일과 서울 기준 분으로 반복 일정을 표현하고 실제 시각은 `timestamptz`에 저장한다.
- 마이그레이션 파일에서는 Supabase CLI가 트랜잭션 경계를 관리하게 했다. 검증 스크립트에는 자체 롤백 경계를 두었다. [CLI 마이그레이션 절차](https://supabase.com/docs/guides/local-development/database-migrations)

### 실행한 검사

- `npm ls @supabase/ssr @supabase/supabase-js --depth=0`으로 기존 설치 버전 0.12.7과 2.119.2를 확인했다. 프로젝트 의존성은 추가하지 않았다.
- Node.js 24.22.3에서 `npm run typecheck`, `npm run lint`(Biome), `npm run build`가 통과했다.
- 가짜 환경변수를 넣은 임시 Node 점검으로 미설정 처리, publishable key 허용, 비밀 키 및 자격 증명이 포함된 URL 거절, 오류 메시지에 입력값이 들어가지 않는 것을 확인했다. TypeScript 모듈을 Node에서 직접 읽는 점검에서만 모듈 유형 경고가 있었다.
- `npm pack`으로 받은 PostgreSQL 17.12 바이너리와 임시 경로에 설치한 `pg` 8.23.1로 로컬 검증을 수행했다. `initdb`와 `pg_ctl`로 Unix 소켓만 사용하는 별도 클러스터를 띄우고, Supabase 역할 기본 권한과 JWT 기반 `auth.uid()`, `auth.jwt()`를 재현했다.
- 새 클러스터에 마이그레이션을 트랜잭션으로 적용하고 검증 SQL을 실행했다. anon 접근 거절, A/B 소유 샵 읽기, 타 샵·민감 컬럼 및 직접 변경 차단, 서울 자정·연속 구간, 교차 테넌트 참조 거절과 허구 데이터 롤백을 확인했다.
- 두 연결로 동일 샵의 같은 슬롯에 온라인·수동 예약을 동시에 쓰는 별도 점검을 수행했다. 두 번째 세션이 잠금을 기다렸고 첫 세션 커밋 뒤 `23505`가 발생했다. 실패 세션을 롤백한 뒤 예약 1건·점유 3개·이벤트 1건만 남았다. 첫 시도에서 점검 코드의 시간 단위가 `5 seconds`여서 PostgreSQL 설정 오류가 발생했고, `5s`로 수정해 새 클러스터에서 다시 검증했다.
- `git check-ignore`로 `.env.local`과 Supabase CLI 임시 디렉터리 제외를 확인했다. 환경변수의 실제 값은 출력하지 않았다.

### 미검증 항목과 사용자 실행 순서

- Supabase CLI·Docker의 전체 스택과 실제 Supabase Auth/JWT, PostgREST, 로그인 세션 및 쿠키 갱신은 검증하지 않았다. 실제 원격 DB에는 접속하거나 SQL을 실행하지 않았다.
- 전체 점유 생성·해제를 보장하는 트랜잭션 RPC, 샵 잠금 순서, 멱등 결과 복구, 예약·결제·알림 동작은 후속 단계다. 이번 동시성 검증은 점유 기본키의 경쟁을 확인했다.
- 로컬 Supabase를 시작하고 마이그레이션 적용을 확인한 뒤 검증 SQL을 실행한다. 앱에서 로컬 클라이언트를 사용할 때만 같은 프로젝트의 공개 URL·publishable key를 `.env.local`의 기존 이름에 설정한다. [실행 순서](R2_DATABASE.md#적용-순서)

## 2026-11-27 · R3 사업자 이메일 인증

### R2 원격 개발 환경 기록

- 사용자 확인에 따르면 R2 마이그레이션과 검증 SQL은 원격 개발용 Supabase SQL Editor에서 정상 실행됐다. R3에서는 원격 DDL을 재실행하거나 스키마를 수정하지 않았다.
- SQL Editor에서 실행한 버전 `20261127020000`은 CLI의 `supabase_migrations.schema_migrations` 이력에 자동 기록되지 않는다. CLI로 관리할 때 원격 스키마와 이력을 대조한 뒤, 스키마가 일치하고 버전이 빠진 경우 적용 이력을 별도로 정리한다. 이번 작업에서 CLI 이력을 변경하지 않았다. [Supabase 마이그레이션 이력](https://supabase.com/docs/guides/deployment/database-migrations)

### 변경 파일과 동작

- `app/auth/`에 사업자 로그인·회원가입·인증 메일 재전송·비밀번호 재설정 요청·이메일 콜백·인증 확인·새 비밀번호·만료 링크 화면, 공통 폼과 Server Action을 추가했다.
- `lib/auth/`에 이메일·비밀번호 검증, 영구 이메일 사용자 판정과 일회용 이메일 링크 처리를 추가했다. 콜백은 허용된 인증 유형과 한 개의 토큰만 받고, 토큰 없이 고정 경로로 이동한다. 사용자 제출 전까지 Supabase OTP를 소비하지 않는다. 인증·복구의 임시 세션은 서버 요청 밖으로 저장하지 않는다.
- `lib/supabase/server.ts`, `proxy.ts`, `app/dashboard/page.tsx`에서 HttpOnly 기반 세션 갱신, 서버 사용자 검증, 비로그인 대시보드 차단과 로그아웃을 구현했다. 글꼴과 색상·간격은 기존 디자인 기준을 사용했다.
- `app/layout.tsx`, `app/globals.css`, `app/setup/page.tsx`에 인증 링크·화면 스타일과 현재 개발 상태를 반영했다. `next.config.ts`는 인증 응답의 공유 캐시를 제한하고 개발 콜백 요청을 Next.js 요청 로그에서 제외한다.
- `README.md`, `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, `docs/R2_DATABASE.md`, `docs/R3_AUTH.md`, `docs/WORKLOG.md`를 갱신했다. 기존 `.env.local`, 의존성, SQL 및 예약 데이터 스키마를 수정하지 않았다.

### 검사 결과

- Node.js 24.22.3에서 `npm run typecheck`, `npm run lint`(Biome), `npm run build`를 통과했다. 기존 `.env.local`을 사용한 설정 형식 검사도 통과했다. 설정값은 출력하지 않았고 연결 검사로 취급하지 않았다.
- 기존 개발 서버가 실행 중이라 같은 디렉터리에 별도 Next 개발 서버를 띄우려던 시도는 개발 출력 잠금으로 중단됐다. 환경변수 파일을 포함하지 않는 임시 복사본을 만들고 `npm ci --offline`, 프로덕션 빌드와 `npm start`로 검증했다. 이 복사본의 Auth 주소는 루프백 모의 서버만 사용했다.
- 프로덕션 사본과 Chrome에서 회원가입·입력 불일치·인증 메일 재요청·미인증 로그인 거절·이메일 인증·로그인·SSR 갱신·새로고침·로그아웃·이전 비밀번호 거절 및 새 비밀번호 로그인을 확인했다.
- 대시보드 직접 접근 및 위조 세션 쿠키 차단, Origin 없는 요청과 외부 Origin의 가입 시도 거절, 중복·잘못된 콜백 파라미터 거절, 외부 리다이렉트 차단, 콜백 GET의 OTP 미소비와 재설정 토큰 재사용 거절을 확인했다. 콜백 응답의 no-store·no-referrer와 쿠키 HttpOnly·SameSite·프로덕션 Secure, 복구 세션 쿠키 미발급을 확인했다.
- Chrome의 320·360·768·1440px에서 인증 화면 또는 인증 흐름을 확인했다. 360px 로그인 화면을 시각 검토했고, 점검한 화면의 가로 넘침은 없었다.

### 미검증 및 사용자 확인

- 실제 원격 개발용 Supabase Auth와 인증 메일 수신, 실제 SMTP 및 실기기 브라우저는 미검증이다. 이번 작업에서 원격 Auth 계정을 생성하거나 메일을 발송하지 않았다.
- 원격 개발 프로젝트에서 Confirm email, Site URL, 가입 인증·재설정 이메일 템플릿을 설정하고 본인 테스트 주소로 가입부터 이메일 인증, 로그인, 새로고침, 로그아웃, 비밀번호 재설정을 확인한다. CLI를 사용할 때는 R2 수동 적용 이력도 대조한다. [R3 설정·검증 순서](R3_AUTH.md)

## 2026-11-27 · 실제 개발 환경 회원가입 연결 수정

- 원인은 `.env.local`의 `NEXT_PUBLIC_SUPABASE_URL`에 입력된 Supabase 관리 대시보드 주소였다. 그 주소로 보낸 가입 요청은 HTTP 405였고, SDK는 Auth JSON 응답으로 해석할 수 없었다. 로컬 Server Action의 HTTP 200은 반환한 폼 상태의 응답이었다. [Supabase 프로젝트 API 주소 안내](https://supabase.com/docs/guides/api/creating-routes)
- `.env.local`의 URL 한 항목을 같은 프로젝트의 API 주소로 바꿨다. 기존 publishable key는 유지했다. `lib/supabase/config.ts`에서 대시보드 주소와 호스팅 API의 서비스 하위 경로를 거절한다. `app/auth/actions.ts`의 실패 로그에는 SDK 오류 종류·코드·상태만 기록한다.
- 실제 원격 프로젝트의 Auth 설정 요청에서 HTTP 200과 이메일 가입 활성 상태를 확인했다. 개발 서버 환경변수 재로딩 후 기존 `/auth/signup` 폼으로 의도적으로 유효하지 않은 주소를 제출했다. Next.js Server Action 로그에서 실제 Auth의 `validation_failed`(HTTP 400)를 확인했다. 이 검증은 계정을 만들거나 메일을 보내지 않았다.
- 타입 검사, Biome, 프로덕션 빌드, URL 유효성 검사를 통과했다.
- 유효한 테스트 주소의 계정 생성과 Gmail 인증 메일 수신은 이번 점검에서 확인하지 않았다.

## 2026-11-27 · R4 사업자 설정

- 사용자가 실제 Supabase 환경에서 R3 가입·이메일 인증·로그인·세션 유지·로그아웃·접근 차단·비밀번호 재설정을 모두 확인했다.
- `app/dashboard/`에 공통 레이아웃과 샵 등록·수정, 시술 등록·수정·공개·비활성화, 주간 영업시간·휴무·휴식시간, 예약 정책·계좌 설정 화면을 추가했다. `lib/dashboard/`에서 R3 서버 인증을 재사용하고, 각 저장 요청도 사용자를 직접 검증한다. 첫 등록은 기존 스키마의 샵 이름과 공개 주소를 사용한다.
- `supabase/migrations/20261127040000_r4_shop_settings.sql`은 R2 테이블과 15분 점유 구조를 유지하고 설정 RPC 네 개만 제공한다. 모든 RPC는 인증된 이메일·샵 소유권을 확인하고, 검색 경로가 비어 있으며 실행은 명시적으로 허용된 `authenticated`에 한한다. 직접 테이블 쓰기 권한은 추가하지 않았다. 같은 샵의 작업을 직렬화하고 샵 정책·시술의 수정 버전을 검사한다.
- 영업·휴식 구간은 서울 기준으로 저장한다. 구간이 없는 요일은 휴무이며, 서로 맞닿는 구간과 자정 종료를 허용한다. 겹치는 구간이나 영업시간보다 넓은 휴식시간은 거절한다. 공개 예약금 시술에는 계좌와 예약금·취소 안내가 모두 필요하다.
- `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/BOOKING_RULES.md`, `docs/ROADMAP.md`, `docs/WORKLOG.md`에 R4 범위와 정책을 반영했다. 기존 홈페이지, R3 인증 파일, R2 SQL 및 환경변수는 수정하지 않았다. 프로젝트 패키지를 추가하지 않았다.

### 실행한 검증

- Node.js 24.22.3에서 `npm run typecheck`, `npm run lint`(Biome), `npm run build`가 통과했다.
- Unix 소켓만 사용하는 별도 PostgreSQL 17.12에서 R2와 R4 마이그레이션을 적용했다. Supabase 역할과 JWT 함수를 재현하고 R2 회귀·R4 검증 SQL을 실행했다. 익명·미인증·타 사업자 접근, 직접 쓰기, 오래된 버전과 잘못된 시간·예약금 입력 거절, 정상 저장과 검증 데이터 롤백을 확인했다.
- 두 PostgreSQL 세션으로 최초 샵 등록을 경합시켜 한 샵만 남는지 확인했다. 예약금 시술 공개와 계좌 삭제를 경합시키면 삭제 요청이 샵 잠금을 기다렸다가 거절됐다.
- 로컬 모의 Auth/API를 실제 PostgreSQL에 연결한 프로덕션 사본과 Chrome에서 대시보드 접근 차단, 샵 등록·수정, 계좌·정책 저장, 시술 공개·비활성화, 영업시간·휴식·휴무 저장, 두 사업자의 설정 격리를 확인했다. 첫 브라우저 검증에서는 오류 뒤 공개 상태 선택이 초기화됐다. 폼 자동 초기화를 막고 재검증해 입력이 유지되는 것을 확인했다. 320·360·1440px에서 점검했고 360px 정책·영업시간 캡처를 확인했다.
- R4 원격 적용과 실제 Supabase Data API의 R4 호출은 수행하지 않았다. 원격 개발 환경에서는 R2 스키마와 CLI 이력을 먼저 대조한다. R4 마이그레이션을 한 트랜잭션으로 적용한 뒤, 별도 검증 SQL을 개발 DB에서 실행한다. SQL Editor를 사용한다면 마이그레이션을 `BEGIN`과 `COMMIT`으로 감싼다. 검증이 통과하면 `/dashboard`에서 설정 저장을 확인한다. [R4 마이그레이션](../supabase/migrations/20261127040000_r4_shop_settings.sql) · [R4 검증 SQL](../supabase/verify/r4_shop_settings.sql)

## 2026-11-27 · R5 고객 예약

- 사용자가 R4 원격 개발 DB 적용과 실제 사업자 설정 테스트를 완료했다고 확인했다.
- `app/book/`, `app/booking-confirmation/`, `app/api/booking/`, `lib/booking/`에 공개 시술·가용 시간 조회, 비회원 예약과 필수 동의, 예약 확인 및 고객 이체 신고를 추가했다. 대시보드에서 공개 링크를 열 수 있다. 취소, 입금 승인·금전 후속 처리 UI, 사업자 예약 관리, 정기 만료 작업, 결제·알림은 후속 범위다.
- `supabase/migrations/20261127050000_r5_customer_booking.sql`과 `supabase/verify/r5_customer_booking.sql`을 추가했다. 예약·점유·이벤트를 한 트랜잭션으로 기록하고, R4와 같은 샵 행 잠금 아래 시술·샵 버전과 시간·금액·계좌를 검증한다. 성공한 요청은 토큰·원본 요청 해시·재시도 키로 먼저 확인한다. 확인 페이지는 Authorization 헤더의 토큰을 검증해 전화번호 끝자리와 필요한 경우의 예약 당시 계좌만 반환한다.
- 가용 시간은 서울 기준 하루씩, 설정값과 90일 중 작은 범위로 조회한다. 시술과 준비시간의 모든 15분 슬롯에 영업·휴식·휴무·점유 조건을 적용한다. 기한이 지난 미신고 건은 가용 조회에서 제외하고 예약 생성 또는 확인 트랜잭션에서 만료·해제한다. 늦은 신고는 금전 확인 표시만 기록한다. 기한 내 신고는 사업자 확인 전까지 점유를 유지한다.
- 예약 RPC는 서버 전용 역할만 실행한다. 설정 화면의 신규 시술 저장은 같은 폼의 요청 키가 이미 처리됐다면 기존 시술을 반환하도록 보완했다. 기존 RLS와 직접 테이블 쓰기 제한은 유지했다.
- `.env.example`, `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/BOOKING_RULES.md`, `docs/ROADMAP.md`, `docs/WORKLOG.md`를 갱신했다. 추가 프로젝트 의존성은 없다.

### 실행한 검증

- Node.js 24.22.3에서 `npm run typecheck`, `npm run lint`(Biome), `npm run build`를 통과했다.
- 별도 PostgreSQL 17.12 클러스터에서 R2·R4 회귀와 R5 SQL 검증을 실행했다. 공개 여부·타 샵 식별자·RPC 역할·정책/시술 버전, 잘못된 시간·휴무·휴식·차단·준비시간·90일 상한, 요청 제한, 예약금 상태, 해제·재예약·늦은 신고, 이벤트 쓰기 강제 실패 시 전체 롤백을 확인했다. 경쟁 검사와 고정 검증 토큰이 한 임시 DB에서 충돌한 경우에는 테스트 토큰의 범위를 구분하고 다시 검증했다.
- PostgreSQL 두 세션에서 같은 시간의 서로 다른 요청은 한 건만 남았고, 동일 요청의 동시 재전송은 기존 결과를 반환했다. R4 설정 저장을 기다리던 고객 요청은 오래된 정책 버전으로 거절됐다.
- Chrome 360px과 실제 PostgreSQL RPC를 호출하는 루프백 API 대역으로 검증했다. 최초 생성 커밋 직후 응답을 잃은 상황에서 새로고침 후 원본 요청으로 확정을 복구했다. 토큰 프래그먼트, 개인정보 마스킹, 입금 안내와 기한 내 신고, 외부 출처·초과 본문·누락 토큰 거절을 확인했다.

### 사용자가 수행할 작업

1. 원격 개발 DB의 R2·R4 스키마와 이력을 확인하고 [R5 마이그레이션](../supabase/migrations/20261127050000_r5_customer_booking.sql)을 한 트랜잭션으로 적용한다. SQL Editor에서는 전체 파일을 `BEGIN`과 `COMMIT`으로 감싼다.
2. [R5 검증 SQL](../supabase/verify/r5_customer_booking.sql)을 별도로 실행한다. 테스트 데이터와 실패 트리거는 롤백된다.
3. 기존 개발 `.env.local`에 같은 프로젝트의 `SUPABASE_SECRET_KEY`를 서버 전용으로 추가한 뒤 서버를 재시작한다. 리버스 프록시에서 요청 origin을 자동 판별할 수 없다면 `BOOKING_APP_ORIGIN`을 지정한다. IP 제한을 사용하려면 신뢰하는 단일 인입 프록시가 외부 입력을 덮어쓰는 IP 헤더 이름을 `BOOKING_TRUSTED_IP_HEADER`로 지정한다. 전체·샵별 제한은 이 설정과 관계없이 동작한다. [Supabase 서버 키 안내](https://supabase.com/docs/guides/getting-started/api-keys)
4. 사업자 대시보드에서 공개 예약 링크를 열고 가상 고객으로 시술·시간 선택, 두 예약금 분기, 확인 링크 재접속을 확인한다. 원격 SQL 적용, 호스팅 Supabase Data API와 실제 모바일 기기는 이번 작업에서 검증하지 않았다.

## 2026-11-27 · R6 사업자 예약 관리

- 사용자가 R5 원격 개발 DB 적용, 검증 SQL 및 실제 고객 예약 흐름을 완료했다고 확인했다.
- `app/dashboard/schedule/`과 `lib/dashboard/schedule.ts`에 서울 기준 일간 일정, 주간·월간 캘린더, 예약 목록·상세, 날짜·상태 필터, 수동 예약, 예약 시간 변경·취소·완료·노쇼, 시간 차단·해제를 추가했다. `app/dashboard/page.tsx`와 메뉴에 오늘의 예약과 상태별 요약을 연결했다.
- `supabase/migrations/20261127060000_r6_owner_schedule.sql`은 기존 점유표 위에 소유자 한정 RPC를 추가한다. 시간 변경은 예약·기존/새 점유·이벤트를 한 트랜잭션에서 갱신한다. 샵 행을 먼저 잠그고 예약 버전을 검사한다. 기존 스냅샷과 예약금 기한은 유지하며, 해제한 차단은 해제 시각을 보관한다. 취소·만료는 해당 예약의 점유만 해제한다.
- 수동 예약금 건은 입금 대기로 저장한다. 예약금이 설정된 예약을 취소하면 금전 후속 확인 필요로 기록하고 기존 입금 상태는 유지한다. 목록·상세 조회 시 만료된 미신고 예약을 정리한다. 예약금 승인·환불 관리·알림 발송은 후속 범위다.
- `docs/BOOKING_RULES.md`, `docs/ARCHITECTURE.md`, `docs/PRD.md`, `docs/ROADMAP.md`, `docs/WORKLOG.md`에 범위와 운영 규칙을 반영했다. 프로젝트 패키지와 환경변수는 추가하지 않았다.

### 실행한 검증

- Node.js 24.22.3에서 `npm run typecheck`, `npm run lint`(Biome), `npm run build`를 통과했다. 첫 lint의 ARIA 속성과 문자열 스타일을 수정한 뒤 다시 검사했다.
- 별도 PostgreSQL 17.12에 R2·R4·R5·R6 마이그레이션을 적용하고 각 검증 SQL을 실행했다. R6는 수동/온라인 충돌, 차단 충돌·해제, 예약 이동 강제 이벤트 실패 후 전체 롤백, 취소 후 같은 시간 재예약과 옛 요청 재시도, 금전 후속 표시, 만료 정리, 허용·거절 상태 전환과 샵 격리를 확인했다. 검증 SQL의 상태 비교식 괄호를 보완하고 초기 데이터베이스에서 재검증했으며 모든 검증 데이터의 롤백을 확인했다.
- PostgreSQL 두 연결로 예약 두 건을 동시에 같은 시간으로 옮겼을 때 패배 요청의 기존 점유가 보존됨을 확인했다. 동일 예약에 상충하는 두 변경은 오래된 버전으로 거절됐고, R6 차단을 기다린 R5 온라인 예약도 거절됐다.
- Chrome 360px에서 실제 PostgreSQL RPC에 연결한 루프백 Auth/API 대역으로 일·주·월간 보기와 오늘 요약, 수동 등록, 충돌 뒤 시간 변경, 취소·재예약, 상태 필터, 차단 해제, 사업자 간 상세 차단을 확인했다. 월간 화면은 320·1440px에서도 가로 넘침이 없었다.

### 사용자 적용 및 미검증

1. R5가 적용된 개발 DB에 [R6 마이그레이션](../supabase/migrations/20261127060000_r6_owner_schedule.sql)을 한 트랜잭션으로 적용한다. SQL Editor를 사용한다면 전체 파일을 `BEGIN`과 `COMMIT`으로 감싼다.
2. 개발 DB에서 [R6 검증 SQL](../supabase/verify/r6_owner_schedule.sql)을 별도로 실행한다. 결과는 `R6 owner schedule checks passed`이며 테스트 데이터와 강제 실패 트리거는 롤백된다.
3. 사업자 계정으로 `/dashboard/schedule`에서 수동 예약, 이동, 취소, 차단·해제를 확인한다. 이번 작업에서 원격 DB에 SQL을 실행하지 않았으며 호스팅 Supabase Data API 및 실제 모바일 기기는 미검증이다.

## 2026-11-27 · R7 예약금 관리

- 사용자가 R6 원격 개발 DB 적용과 실제 사업자 예약 관리 테스트를 완료했다고 확인했다.
- `app/dashboard/deposits/`와 `lib/dashboard/deposits.ts`에 입금 대기·이체 신고·확인 완료·금전 후속·처리 기록 목록과 상세를 추가했다. 대시보드 요약, 예약 상세, 고객 확인 화면과 상태를 연결했다.
- `supabase/migrations/20261127070000_r7_deposits.sql`은 소유자 검증 뒤 샵 행과 예약 행을 순서대로 잠그고 예약 버전을 확인한다. 예약금과 실제 입금액이 일치하면 예약을 확정한다. 불일치는 금액·사유만 기록하며, 종료 예약의 수납과 환불 기록은 일정과 점유를 유지한다. 수동 환불 기록 누계는 확인한 입금액을 넘을 수 없고, 재전송은 기존 이벤트를 반환한다.
- 기한이 지난 미신고 건은 해당 예약의 점유만 해제한다. 신고된 예약은 자동으로 만료되지 않는다. 종료 예약의 첫 늦은 신고나 최초 실제 수납 확인은 금전 검토를 다시 열 수 있다. 자동 만료 배치 함수는 DB 마이그레이션 소유자로만 실행하도록 제한했다.
- 기존 예약 스냅샷과 상태 제약, RLS 및 직접 테이블 쓰기 제한을 유지했다. 자동 결제·송금·환불·알림을 연결하지 않았다. `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/BOOKING_RULES.md`, `docs/ROADMAP.md`, `docs/WORKLOG.md`를 갱신했다.

### 실행한 검증

- Node.js 24.22.3에서 `npm run typecheck`, `npm run lint`(Biome), `npm run build`가 통과했다.
- 별도 PostgreSQL 17.12에서 R2·R4·R5·R6 회귀와 R7 검증 SQL을 실행했다. 온라인·수동 승인, 같은 키 재시도와 변경 요청 거절, 실제 입금액 불일치, 이미 종료된 예약의 수납, 늦은 신고로 재검토 열기, 취소 후 수동 환불·금액 상한, 사업자 격리, Cron 권한 차단을 확인했다.
- PostgreSQL 두 세션에서 승인 먼저, 자동 만료 먼저, 승인 요청이 잠금 대기 중 기한을 넘긴 경우, 취소 먼저를 각각 검증했다. 만료 또는 취소가 먼저인 경우 예약이 다시 열리지 않았고, 먼저 승인된 예약은 점유가 유지됐다. 로컬에서 배치 함수를 실행해 잠긴 샵을 건너뛰는 것도 확인했다.
- Chrome 360px과 실제 PostgreSQL RPC를 호출하는 로컬 Auth/API 대역으로 수동 예약금 대기, 금액 차이 기록, 사업자 승인, 취소 후 수동 환불, 분류·대시보드 요약, 다른 사업자의 상세 차단을 확인했다. 320·1440px 예약금 목록에 가로 넘침이 없었다.

### 사용자 적용 및 미검증

1. R6가 적용된 개발 DB에 [R7 마이그레이션](../supabase/migrations/20261127070000_r7_deposits.sql)을 한 트랜잭션으로 적용한다. SQL Editor에서는 전체 파일을 `BEGIN`과 `COMMIT`으로 감싼다.
2. [R7 검증 SQL](../supabase/verify/r7_deposits.sql)을 별도로 실행한다. `R7 deposit checks passed`를 확인하고 사업자 메뉴의 예약금 목록에서 합성 데이터로 실제 API 경로를 점검한다.
3. [정기 만료 설정 안내](ARCHITECTURE.md#r7-정기-만료-설정)에 따라 Supabase Cron 작업을 등록하고 실행 이력을 확인한다. 이번 작업에서 원격 적용·실제 Supabase Cron 등록·실기기 검증을 수행하지 않았다.

## 2026-11-27 · R8 사업자 알림

- `supabase/migrations/20261127080000_r8_notifications.sql`과 `supabase/verify/r8_notifications.sql`을 추가했다. 예약 이벤트와 앱 알림·발송 작업을 같은 트랜잭션에 저장한다. 입금 확인 지연은 예약당 한 번, 당일 예약 안내는 서울 날짜와 예약 단위로 생성한다. 샵 소유권을 검증한 RPC만 알림·기기를 조회하거나 변경한다.
- `app/dashboard/notifications/`, 대시보드 메뉴, 인증 이동 경로에 알림 목록·개수·읽음 상태·기기 등록/해제·푸시 설정을 추가했다. `app/manifest.ts`, `public/notification-sw.js`, PWA 아이콘을 추가했다. 클릭 경로는 로그인 후에도 동일한 예약·예약금 상세를 열고, 타 사업자 알림은 열리지 않는다.
- `app/api/internal/notifications/`와 `lib/notifications/`에 VAPID 발송 워커를 구현했다. 기기별 유일성, 90초 lease, 최대 5회 재시도, 실패 기록, 404·410 구독 정리, 검증한 제공사 주소에 대한 TLS 연결을 적용했다. 푸시에는 알림 종류와 UUID만 담는다. `web-push@4.0.0`은 VAPID 서명과 표준 암호화에, `@types/web-push@3.6.4`는 타입 검사에 사용한다.
- `.env.example`, PRD, 아키텍처, 예약 규칙, 로드맵, [R8 운영 안내](R8_NOTIFICATIONS.md)를 갱신했다. 로드맵에는 사업자 알림을 R8로 배치하고 개발 배포 이후의 기존 순서를 유지했다.

### 실행한 검증

- Node.js 24.22.3 / npm 11.19.1에서 `npm run typecheck`, `npm run lint`(Biome), `npm run build`가 모두 통과했다.
- 격리된 PostgreSQL 17.12에 R2·R4~R8을 새로 적용했다. R2·R4~R7 검증 SQL과 R8 검증 SQL이 통과했다. 여섯 종류 생성, 예약 롤백 시 알림·작업 롤백, 중복 억제, 읽음 상태, 푸시 꺼짐 동안 생긴 작업의 발송 억제, 재시도·상한·구독 정리, 사업자·익명 권한을 확인했다. 두 서비스 역할 세션에서 동시 claim, lease 만료 후 회수, 지난 lease의 완료 요청 거절도 확인했다.
- Chrome 320·360·1440px에서 가로 넘침, 읽음 전환·개수, 기기 설정, 비로그인 클릭 후 상세 도착, 다른 사업자 접근 차단을 확인했다. 로컬 Auth/API 대역은 실제 PostgreSQL RPC를 호출했다. 매니페스트와 Service Worker는 브라우저에 로드했고 기기 구독 API는 모의했다. 내부 워커의 인증 거부·허용도 루프백에서 확인했다.
- 실제 `web-push` 라이브러리로 VAPID 헤더와 암호화 본문을 만들었다. 모의 DNS·HTTPS로 사설 주소 차단, 리다이렉트 미추적, 429 재시도, 410 만료 판단을 확인했다. 모의 Service Worker 이벤트로 개인정보가 표시되지 않고 클릭 경로가 앱 내부로 제한되는 것을 확인했다.
- PostgreSQL에서 변경 CTE를 함수 반환식에 직접 넣을 수 없어 최상위 CTE의 결과를 변수에 담도록 수정했다. 브라우저에서는 로그인 뒤 예약 상세가 열려도 주소가 중간 알림 경로로 남는 점을 발견해, 로그인 서버가 소유권을 확인한 뒤 상세 주소로 직접 이동하도록 수정하고 재검증했다.

### 미검증 및 사용자 적용

- 원격 DB에 SQL을 실행하거나 Cron을 등록하지 않았다. 호스팅 Supabase API, 실제 제공사 접수, iOS·Android 실기기 수신은 확인하지 않았다.
- R7 적용을 확인한 후 R8 마이그레이션과 검증 SQL을 순서대로 실행한다. SQL Editor로 적용하면 CLI 이력을 따로 관리한다. [R8 운영 안내](R8_NOTIFICATIONS.md)에 따라 VAPID·워커 환경변수와 Vault·Cron을 설정하고 실제 휴대폰에서 수신과 클릭을 확인한다.

## 2026-11-27 · R9 통합 검증과 HTTPS 배포 준비

- 사용자가 개발 DB의 R1~R8 적용과 주요 사용자 흐름을 확인했다고 보고했다. 이번 작업은 발표·제한 사용자 테스트용 배포 준비와 회귀 검증을 진행했다.
- `supabase/migrations/20261127090000_r9_deploy_hardening.sql`을 추가했다. 샵의 예약 창을 오늘 포함 90일로 제한하고, 초과한 기존 설정의 정책 버전을 올린다. 기존 시술 RPC는 수정에 사용하며 새 시술은 요청 키가 필요한 경로로 생성한다. 공개 API는 신뢰한 IP 요청 제한을 먼저 확인하고, 존재하는 샵을 UUID로 구분한다. 예약 확인과 입금 신고는 서로 다른 한도를 사용한다. 공개 주소가 바뀌어도 완료된 원래 예약 요청을 복구할 수 있다.
- `app/auth/email-link/`와 인증 서버 액션을 추가했다. 신규 이메일 템플릿은 토큰을 URL fragment로 전달한다. 서버에 전달한 뒤 사용자가 확인 또는 재설정을 제출할 때 OTP를 교환한다. 대시보드는 로그아웃 이후 히스토리에서 복원될 때 세션을 다시 확인한다. Service Worker는 페이지나 API 응답을 저장하지 않는다.
- 예약 정책의 90일 상한, 지연된 입금 확인 표시, 입금 합계와 1회 환불 기록의 한계를 화면에 반영했다. 알림 워커는 기존 최대 24건 배치를 병렬 처리해 제공사 응답이 느릴 때 Cron 요청과 lease에 소요되는 시간을 줄였다.
- 인증·권한·토큰·예약금·푸시 경계를 점검했다. 분산 허위 예약, 전화번호 소유 확인, 다건 수납·분할 환불 원장은 제한 사용자 테스트 후 결정할 항목으로 남겼다. 신규 패키지는 추가하지 않았다. [R9 배포 안내](R9_DEPLOYMENT.md)

### 실행한 검증

- Node.js 24.22.3 및 npm 11.19.1에서 `npm run typecheck`, `npm run lint`, `npm run build`가 통과했다. `npm audit`는 알려진 취약점 0건으로 응답했다. 격리된 로컬 빌드에서 합성 서버 비밀값이 브라우저 정적 번들에 포함되지 않음을 확인했다.
- PostgreSQL 17.12에서 R2·R4~R9를 순서대로 적용하고 해당 검증 SQL 전부와 픽스처 롤백을 확인했다. 200일 기존 값의 90일 변환과 revision 증가, 시술 생성 우회 경로 차단, 요청 키 재사용 검증, 이름이 바뀐 샵의 예약 복구, 한 IP가 제한된 뒤 다른 사용자와 API에 한도가 전가되지 않는지 확인했다. R4·R5 검증은 R9 전후 양쪽 스키마의 정상 진입점을 사용하도록 맞췄다.
- 기존 두 세션 테스트로 예약 생성 경쟁·동일 요청 재시도, 설정 변경·시간 변경·차단과 예약의 경합, 승인·취소·만료 경합, 알림 lease 회수 및 지난 lease 요청 거절을 검증했다.
- 로컬 HTTPS의 Chrome에서 가입·확인·로그인, 샵·정책·영업시간·시술 설정, 비회원 예약·입금 신고, 사업자 승인·이동·취소·수동 환불 기록, 알림 목록, 교차 사업자 차단, 로그아웃 후 뒤로 가기, 비밀번호 재설정을 연속으로 검증했다. 실제 PostgreSQL RPC를 호출하는 로컬 API와 합성 Auth를 사용했다. 320·360·1440px과 HTTP 오류 응답, 작업 실행 키 검사를 확인했다.
- Web Push 라이브러리의 VAPID 암호화 요청은 실행했고, 모의 DNS·HTTPS로 사설 주소와 리다이렉트 차단, 429·410 처리와 Service Worker 클릭 경로를 재검증했다.

### 미검증 및 사용자 적용

- 원격 DB에 R9 마이그레이션을 실행하거나 Render 서비스를 만들지 않았다. 호스팅 HTTPS, 실제 SMTP 메일, 신뢰 IP 헤더 덮어쓰기, 원격 Cron과 휴대폰 푸시 수신은 실제 데모 환경에서 확인해야 한다.
- [R9 배포 안내](R9_DEPLOYMENT.md)에 따라 데모 DB에 마이그레이션을 먼저 적용하고, SQL Editor로 적용한 버전의 CLI 이력을 스키마와 대조한다. Render 설정과 Supabase Site URL·이메일 템플릿·Cron을 맞춘 뒤 새 인증 메일과 합성 예약으로 배포 직후 흐름을 확인한다.

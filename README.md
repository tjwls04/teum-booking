# 틈예약

샵인샵·1인 프리랜서 사업자를 위한 예약 관리 웹서비스입니다. R1에서는 틈예약 소개, 개발 상태 안내, 로컬 런타임 확인을 제공합니다. R2에서는 Supabase 마이그레이션과 서버·브라우저 클라이언트 기반을 제공합니다. R3에서는 사업자 이메일 인증과 대시보드 보호를 제공합니다. 예약, 결제, 알림은 후속 단계입니다.

## 로컬 실행

macOS arm64에서 Node.js **24.22.3 LTS**와 npm **11.19.1**로 검증했습니다. nvm 사용자는 `nvm install`과 `nvm use`로 [`.nvmrc`](.nvmrc)의 버전을 적용할 수 있습니다. nvm이 없는 Mac에서는 공식 릴리스에서 해당 Node 버전의 설치 파일을 받을 수 있습니다. [Node.js 24.22.3 LTS](https://nodejs.org/en/blog/release/v24.22.3)

```sh
npm ci
npm run dev
```

- [틈예약 소개](http://localhost:3000/)
- [개발 상태](http://localhost:3000/setup)
- [런타임 health API](http://localhost:3000/api/health)에서 HTTP 200과 `{"status":"ok"}`를 확인합니다.

소개 페이지는 환경변수 없이 실행할 수 있습니다. Supabase 마이그레이션은 [R2 데이터베이스 안내](docs/R2_DATABASE.md)에, 이메일 템플릿 설정과 로그인 테스트는 [R3 인증 안내](docs/R3_AUTH.md)에 있습니다.

```sh
npm run typecheck
npm run lint
npm run build
npm start
```

`npm start`는 빌드 후 프로덕션 서버를 시작합니다. 같은 포트를 쓰려면 개발 서버를 먼저 종료합니다.

## 이전 프로토타입을 이미 받았다면

- 이전 소스 폴더는 별도로 보관합니다. 이 폴더 위에 통째로 덮어쓰지 않습니다.
- 기존 문구, 고객 흐름, 예약 규칙, 테스트 시나리오는 참고할 수 있습니다. 새 화면의 시각 기준은 [DESIGN.md](docs/DESIGN.md)에 있습니다.
- 기존 Vinext/Vite/Cloudflare D1/ChatGPT 로그인은 새 프로젝트의 실행·인증·DB 구조와 다릅니다.
- 기존 프로젝트의 `AGENTS.md`에는 예약금 보류 및 Sites 인증 등 이전 결정이 있습니다. 새 프로젝트는 이 묶음의 최신 문서와 사용자의 후속 지시를 따릅니다.
- 기존 코드가 없어도 이 묶음만으로 시작할 수 있습니다. 이전 DB의 데이터 삭제·이전 작업은 포함하지 않습니다.

## 파일 안내

| 파일 | 역할 |
| --- | --- |
| `AGENTS.md` | 코딩 에이전트의 작업 범위와 검증 규칙 |
| `docs/PROJECT_CONTEXT.md` | 사용자의 확인된 요구와 현재 작업 방식 |
| `docs/PRD.md` | 이번 제품의 범위, 기능, 완료 기준 |
| `docs/DESIGN.md` | 확정한 색상·서체·화면 설계 기준 |
| `docs/WORKLOG.md` | R1 구현과 로컬 검증 결과 |
| `docs/BOOKING_RULES.md` | 시간 중복 방지, 예약금, 취소·만료 규칙 |
| `docs/USER_FLOW.md` | 고객·사업자 흐름과 화면 구성 |
| `docs/ARCHITECTURE.md` | Next.js/Supabase 구조와 데이터 접근 원칙 |
| `docs/ROADMAP.md` | 작은 단위로 구현할 순서 |
| `docs/TEST_PLAN.md` | 실제 DB·기기에서 확인할 핵심 조건 |
| `docs/DECISIONS.md` | 확정된 요구, 제안한 기본값, 후속 결정 |
| `docs/SOURCES.md` | 현재 도구·연동 조건의 공식 참고 자료 |
| `prompts/01-bootstrap.md` | 지금 실행할 첫 요청문 |
| `prompts/review-task.md` | 기능 구현 후 독립 검토 요청문 |

## 작업 분담

사용자는 코드·GitHub·Supabase·Render 계정을 소유하고 관리합니다. ChatGPT는 요구사항·설계·작업 분할·검토 기준을 맡고, Cursor 안의 Codex 또는 Claude Code가 로컬 파일을 수정하고 검증합니다.

계약, 계정 연결, 실기기 확인처럼 사용자 환경이 필요한 단계는 구현과 구분하여 보고합니다. 미실행 검증을 통과로 표시하지 않습니다.

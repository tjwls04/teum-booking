# R3 사업자 인증 설정과 검증

## Supabase 개발 프로젝트 설정

기존 `.env.local`에 연결된 개발 프로젝트에서 설정한다.

1. Supabase Authentication의 이메일 공급자에서 이메일·비밀번호 가입과 **Confirm email**을 켠다. 이 설정이 이메일 소유 확인을 강제한다. 앱 자체의 신규 비밀번호 기준은 12자 이상, UTF-8 기준 72바이트 이하다. [Supabase 이메일·비밀번호 인증](https://supabase.com/docs/guides/auth/passwords)
2. URL Configuration의 **Site URL**에 사용자가 열 수 있는 틈예약 개발 앱의 origin을 설정한다. 같은 Mac에서만 테스트한다면 `http://localhost:3000`을 사용할 수 있다. 끝에 슬래시를 붙이지 않는다. 이메일 링크는 이 주소에서만 시작하며, 요청에 들어온 외부 URL이나 `next`는 리다이렉트에 사용하지 않는다.
3. Authentication의 이메일 템플릿에서 **Confirm sign up**과 **Reset password**의 링크를 아래와 같이 바꾼다. 환경을 바꿔 다시 테스트할 때는 기존 메일 대신 새 메일을 요청한다. [Supabase 이메일 템플릿](https://supabase.com/docs/guides/auth/auth-email-templates)

가입 인증 링크

```html
<a href="{{ .SiteURL }}/auth/email-link#type=email&amp;token_hash={{ .TokenHash }}">이메일 인증하기</a>
```

비밀번호 재설정 링크

```html
<a href="{{ .SiteURL }}/auth/email-link#type=recovery&amp;token_hash={{ .TokenHash }}">비밀번호 재설정하기</a>
```

4. 실제 수신 테스트에는 본인이 관리하는 주소만 사용한다. 기본 메일 서비스는 프로젝트 팀 주소와 발송량을 제한한다. 외부 주소로 시험하려면 프로젝트 SMTP 설정을 준비한다. [Supabase SMTP 안내](https://supabase.com/docs/guides/auth/auth-smtp)
5. HTTPS 환경의 인증 응답은 공유 캐시를 우회하도록 유지한다. 배포 환경에 요청 로그나 추적을 연결할 경우 `/auth/callback`의 쿼리와 인증 폼 본문이 기록되지 않도록 설정한다.

## 사용자가 확인할 흐름

- 홈페이지의 **사업자 로그인**에서 가입한다. 인증 전에 로그인하면 인증이 필요하다는 안내가 나오는지 확인한다. 이메일에서 링크를 열고 **이메일 인증 완료하기**를 누른 뒤 로그인한다. 메일을 받지 못하면 인증 메일 다시 보내기를 확인한다.
- 로그인하면 `/dashboard`에서 본인 이메일과 로그아웃을 확인한다. 새로고침 후에도 로그인 상태가 유지되는지, 로그아웃 후에 `/dashboard` 직접 접속이 로그인으로 돌아가는지 확인한다.
- 로그인 화면에서 비밀번호 재설정 메일을 요청한다. 메일 링크에서 새 비밀번호를 입력하고 새 비밀번호로 로그인한다. 같은 재설정 링크를 다시 제출하면 거절되어야 한다.

## 인증 경계

- 신규 메일의 토큰은 URL fragment에 들어 있다. 링크 화면이 fragment를 주소에서 지우고 같은 출처의 서버 액션으로 전달한다. 서버는 10분짜리 HttpOnly 쿠키를 발급한다. 이전 링크의 콜백 GET은 만료 전 호환 경로다. 메일 스캐너의 GET에는 OTP를 교환하지 않는다. 사용자 제출 시 서버에서 Supabase OTP를 교환하고, 인증·재설정에 필요한 임시 세션은 요청 안에서만 사용한다.
- Proxy는 대시보드 요청의 세션 쿠키를 갱신해 현재 요청과 응답에 함께 반영한다. 대시보드 페이지는 Supabase Auth의 `getUser()`로 인증된 영구 이메일 사용자인지 검증한다. 로그인 세션 쿠키는 HttpOnly이며 R3 화면에서는 서버가 Auth를 호출한다.
- 가입, 인증과 재설정은 틈예약 예약 데이터에 쓰지 않는다. R3의 대시보드는 로그인 계정 정보만 표시한다.

import Image from "next/image";
import Link from "next/link";

export default function HomePage() {
  return (
    <main>
      <section className="shell hero" aria-labelledby="home-title">
        <div className="hero-copy">
          <p className="eyebrow">샵인샵 · 1인 프리랜서</p>
          <h1 id="home-title" className="display-title">
            <span>1인 샵의 예약을 </span>
            <span>한곳에서 </span>
            <span>관리합니다</span>
          </h1>
          <p className="hero-description">
            시술 중에도 고객은 링크에서 빈 시간을 고르고,
            사업자는 휴대폰으로 하루 일정을 확인하는 예약 서비스를 만들고 있습니다.
          </p>
          <a className="primary-link" href="#about">
            서비스 소개 <span aria-hidden="true">↓</span>
          </a>
          <p className="early-status">
            <span aria-hidden="true" />
            개발 초기 단계 · 예약 기능 준비 중
          </p>
        </div>
        <div className="hero-photo">
          <Image
            src="/images/salon-chair.jpg"
            alt="나무 바닥과 거울 앞에 놓인 갈색 시술 의자"
            fill
            preload
            sizes="(max-width: 767px) calc(100vw - 40px), (max-width: 1440px) 47vw, 610px"
          />
        </div>
      </section>

      <section id="about" className="about-section" aria-labelledby="about-title">
        <div className="shell about-grid">
          <div>
            <p className="eyebrow">서비스 소개</p>
            <h2 id="about-title" className="section-title">예약 링크에서<br />하루 일정까지</h2>
          </div>
          <div>
            <dl className="feature-list">
              <div>
                <dt>고객의 예약</dt>
                <dd>가입 없이 예약 링크를 열고 원하는 시술과 빈 시간을 고릅니다.</dd>
              </div>
              <div>
                <dt>사업자의 일정</dt>
                <dd>고객 예약과 미리 막아 둔 시간을 휴대폰에서 한눈에 확인합니다.</dd>
              </div>
            </dl>
            <Link className="text-link" href="/setup">
              현재 개발 상태 확인 <span aria-hidden="true">↗</span>
            </Link>
          </div>
        </div>
      </section>
    </main>
  );
}

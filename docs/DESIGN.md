# 틈예약 디자인 기준

확정일 2026-11-27 (Asia/Seoul)

## 콘셉트

**Premium Editorial × Modern SaaS.** 넓은 여백과 정교한 그리드, 자연스러운 타이포그래피로 1인 샵의 공간과 업무를 보여준다.

- 에디토리얼 웹 사례에서 여백과 그리드 운용을 참고한다. [Awwwards](https://www.awwwards.com/)
- 큰 타이포그래피와 이미지의 배치를 참고한다. [Polpharma Biologics](https://www.polpharmabiologics.com/)
- 따뜻한 중성색과 실제 공간을 담은 사진을 참고한다. [Aesop](https://www.aesop.com/)
- 제품 화면의 명확한 정보 계층과 정돈된 레이아웃을 참고한다. [Linear](https://linear.app/)

## 공통 색상과 서체

| 용도 | 값 | CSS 토큰 |
| --- | --- | --- |
| 배경 | `#F4F3EF` | `--color-paper` |
| 메인 컬러 | `#192D29` | `--color-pine` |
| 보조 컬러 | `#779B8D` | `--color-sage` |
| 보조 배경 | `#D5E4D8` | `--color-mist` |
| 기본 텍스트 | `#222222` | `--color-ink` |

한글은 Pretendard를 사용한다. 영문은 Helvetica Neue, Helvetica, Arial 순으로 적용한다. 제목과 본문 사이에 크기·굵기·행간 차이를 두고 한글은 단어 단위로 줄을 바꾼다. 연한 녹색은 선이나 상태 표시점에 사용하며 상태 문구를 함께 제공한다.

## 화면별 원칙

- 홈페이지는 브랜드 경험을 우선한다. 실제 샵 사진과 구현된 제품 화면을 중심으로 서비스를 설명한다. R1에서는 실제 샵 사진과 현재 개발 상태를 사용한다.
- 예약·관리 화면은 사용성을 우선한다. 시술·시간·상태·다음 행동을 먼저 보여 주고, 키보드 포커스와 입력 라벨을 명확히 표시한다.
- 모바일 대응은 필수다. 좁은 화면에서는 단일 열을 기본으로 하고, 주요 링크와 버튼은 44px 이상의 터치 영역을 확보한다.

## 금지 사항

- AI 생성 느낌의 일러스트 및 3D 오브젝트
- 과도한 그라데이션과 글래스모피즘
- 불필요한 카드·아이콘·장식용 영문
- 지나치게 둥근 버튼과 컨테이너
- 가짜 고객 후기 및 근거 없는 광고 문구

## R1 에셋 출처

- 소개 사진은 Ron Lach가 촬영한 샵 실내 사진을 Pexels 라이선스에 따라 사용한다. [사진 원본](https://www.pexels.com/photo/a-shot-of-an-armchair-in-a-beauty-salon-10317450/) · [Pexels 라이선스](https://www.pexels.com/license/)
- Pretendard Variable v1.3.9를 앱에서 직접 제공하고 OFL 1.1을 글꼴과 함께 보관한다. [공식 릴리스](https://github.com/orioncactus/pretendard/releases/tag/v1.3.9) · [OFL 1.1](../app/fonts/OFL.txt)

# OT Cooling CRM

데이터센터 냉각설비 제조사의 영업 · 설계 · 현장 · 서비스 · 고객을 하나의 Salesforce org 위에 연결한 CRM입니다.
장비 한 대의 이상 신호가 **복구 → 재발 방지 → 계약 갱신**까지 끊기지 않고 이어지도록 설계했습니다.

`Salesforce` `Apex` `LWC` `Flow` `Agentforce` `Experience Cloud` `GitHub Actions`

<img src="docs/images/asset-history.png" width="900">

> 원인 확정 타임라인 — 2022년 시공 기록과 2026년 장애가 같은 화면에 놓입니다.

---

## 왜 만들었나

데모 시나리오의 장애 한 건을 시간 단위로 분해하니, **고객이 체감한 복구 시간 6시간 51분 중 실제 수리는 2시간**이었습니다.
나머지 대부분은 장비를 특정하고, 계약과 보증을 확인하고, 도면과 변경 이력을 대조하는 데 쓰였습니다.

같은 장비를 보는 다섯 역할(고객 · 서비스 · 설계 · 현장 · 영업)이 앞 단계의 기록을 이어받지 못해, 각자 필요한 맥락을 처음부터 다시 만들고 있었습니다.

**개선 대상은 수리 시간이 아니라 수리를 시작하기 전의 정보 탐색이었습니다.**

→ 상세: [문제 정의와 설계](docs/problem-and-design.md)

---

## 무엇을 만들었나

한 건의 이상 신호가 네 장면을 거쳐 예방과 다음 제안으로 확장됩니다.

| | 장면 | 구현 |
| --- | --- | --- |
| 01 | **고객 접점** | Experience Cloud 고객 포털 · Agentforce 상담(MIAW) · 상담사 인계 · Case 자동 생성 |
| 02 | **출동 판단** | AI 출동 브리핑 · 동일 Hall 12대 비교 · Slack Swarming 전문가 연결 · Work Order 발행 |
| 03 | **현장 복구** | Field Service Mobile · 자산 이력 통합 조회 · 조치 결과 즉시 반영 |
| 04 | **예방 확장** | 근본 원인 분석 · 예방 작업 11건 자동 발행 · 점검표 개정 · 갱신 Opportunity |

<img src="docs/images/customer-portal.png" width="900">

> 고객 포털 — 보유 장비 20대 중 주의 1대가 표시되고, 유량 추세와 알림을 고객이 직접 확인합니다.

<img src="docs/images/trend-comparison.png" width="900">

> AI 출동 브리핑 — 12대 모두 **판정은 정상**인데 CDU-A-07만 **추세가 이상**입니다.
> 사양 대비 합격 여부와 기준선 대비 변화를 분리해 다루도록 설계한 이유입니다.

<img src="docs/images/capa-summary.png" width="900">

> 한 대의 조치가 시정 1건과 나머지 11대의 예방 작업으로 확장됩니다.

→ 전체 화면과 흐름: [데모 시나리오](docs/demo-walkthrough.md)

### AI의 역할과 경계

Agentforce는 판단 근거를 준비하고, **결정과 승인은 사람이 합니다.**

```
AGENT 후보·근거 준비 → HUMAN 판단·승인 → FLOW 후속 업무 발행 → RULE 미승인 상태 차단
```

---

## 결과

| | AS-IS | TO-BE |
| --- | --- | --- |
| 고객 체감 복구 시간 | 6시간 51분 | **4시간 10분** (−39%) |
| 접수 · 맥락 재구성 | 3시간 12분 | **31분** |

현장 이동 45분 · 점검/수리 2시간 · 안정화 54분은 동일합니다.
**데모 시나리오 기반 예상치이며 실제 운영 실적이 아닙니다.**

→ 구간별 상세: [검증 결과](docs/results.md)

---

## 기술 스택

| 구분 | |
| --- | --- |
| 플랫폼 | Salesforce Enterprise Edition · Service Cloud · Experience Cloud |
| 개발 | Apex · Lightning Web Components · Flow · SOQL · Validation Rule |
| 서비스 | Case · Work Order · Problem · Entitlement · Milestone · Business Hours |
| AI | Agentforce · Prompt Builder · Slack Swarming |
| DevOps | GitHub Actions · Salesforce CLI · sfdx-git-delta |
| 개발 도구 | Claude · Agentforce Vibes |

→ 객체 관계와 SLA 구성: [데이터 모델](docs/data-model.md)

---

## 시작하기

**요구 사항** — Salesforce CLI (`sf`) · Node.js 18 이상 · [sfdx-git-delta](https://github.com/scolladon/sfdx-git-delta) · 배포 가능한 Salesforce org

```bash
git clone https://github.com/sf-team-1to10/ot-cooling-crm.git
cd ot-cooling-crm

# org 인증
sf org login web --alias t0int

# 소스 배포
sf project deploy start --target-org t0int

# Apex 테스트
sf apex run test --target-org t0int --test-level RunLocalTests --wait 20
```

Experience Cloud 사이트와 Agentforce는 배포 후 org에서 활성화가 필요합니다.

---

## 개발 워크플로

`main` 대상 PR에서 `force-app` 또는 워크플로 파일이 바뀌면 GitHub Actions가 자동으로 검증합니다.

```
main 대상 PR
    ↓
변경 메타데이터만 추출              sfdx-git-delta
    ↓
Production org 대상 배포 검증        --dry-run
    ↓
Apex 변경이 있으면 테스트 실행       RunSpecifiedTests
    ↓
검증 통과 시 자동 병합              gh pr merge --auto
```

**Git은 기록용이고, 어떤 org에도 자동으로 배포하지 않습니다.** 워크플로는 검증(dry-run)까지만 수행하며 실제 배포는 org에서 직접 합니다.

→ 검증 단계와 판단 배경: [CI/CD 운영 기준](docs/ci-cd.md)

---

## 저장소 구조

```
force-app/main/default/
├── classes/                Apex 클래스 및 테스트 클래스
├── lwc/                    Lightning Web Components
├── objects/                표준 · 커스텀 객체, 필드, 레코드 타입
├── flows/                  Flow 정의
├── genAiPromptTemplates/   Agentforce 프롬프트 템플릿
├── permissionsets/         역할별 권한 세트
├── flexipages/             레코드 페이지 구성
└── experiences/            고객 포털
docs/                       설계 · 운영 문서
.github/workflows/          CI 워크플로
```

---

## 팀

Salesforce AI CRM 엔지니어 과정(AI CRM Track 2기) 팀 프로젝트 · 2026.08 – 2026.09 · 5주

| 역할 | 이름 | 담당 | |
| --- | --- | --- | --- |
| PM · Team Lead | 조형준 | 프로젝트 운영 · 프로세스 기획 | [@chorea0408-png](https://github.com/chorea0408-png) |
| PL · Technical Lead | 장수민 | 기술 설계 · 구현 총괄 · 통합 org 및 릴리스 | [@sooe2min](https://github.com/sooe2min) |
| Admin · Platform Enablement | 이유주 | 환경 · 데이터 · 권한 구성 · 발표 | [@Unuzual](https://github.com/Unuzual) |
| AE · Implementation & Quality | 이유민 | 프로젝트 제안 · 기능 구현 · 통합 검증 | [@dbals12](https://github.com/dbals12) |
| AL · Process Flow Owner | 김현우 | 프로젝트 제안 · 업무 흐름 · 핵심 구현 | [@hyunw0000](https://github.com/hyunw0000) |

이 프로젝트는 AI 개발 도구(Claude · Agentforce Vibes)를 적극적으로 활용해 진행했습니다.

---

## 문서

| | |
| --- | --- |
| [문제 정의와 설계](docs/problem-and-design.md) | AS-IS 시간 분해 · 역할별 단절 · TO-BE · AI 역할 경계 |
| [데이터 모델](docs/data-model.md) | 객체 관계 · 커스텀 객체 · SLA 구성 |
| [데모 시나리오](docs/demo-walkthrough.md) | SCENE 01–04 전체 화면과 흐름 |
| [검증 결과](docs/results.md) | 구간별 소요 시간 비교 |
| [CI/CD 운영 기준](docs/ci-cd.md) | PR 검증 흐름 · 의사결정 배경 · CD 도입 조건 |

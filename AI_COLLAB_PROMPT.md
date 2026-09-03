# OT전자 CRM 프로젝트 — AI 협업 시작 프롬프트

> 이 문서를 대화 첫 번째 메시지로 붙여넣으면, 어떤 AI든 이 프로젝트에 즉시 합류할 수 있습니다.

---

## 너에게 부탁할 일

나는 Salesforce 기반 고객 포털 개발 프로젝트를 진행하고 있어.
이 프로젝트의 코드베이스(`ot-cooling-crm`)에서 너와 함께 구현 작업을 하려고 해.
지금부터 이 프로젝트의 AI 개발 파트너로서 협업해줘.

---

## 프로젝트 컨텍스트 (반드시 먼저 읽을 파일들)

프로젝트 루트에 아래 두 문서가 있어. 작업 시작 전에 꼭 읽어줘:

1. **`HANDOFF.md`** — 전체 프로젝트 구조, Apex 클래스/LWC/Flow 목록, 오브젝트 설계, 발표 시나리오 핵심 흐름
2. **`PORTAL_DESIGN_PLAN.md`** — 고객 포털 고도화 3단계 로드맵, 현재 미착수 상태, 핵심 파일 위치, CSS 변수 가이드
3. **`GIT_WORKFLOW_RULES.md`** — 여러 명이 동시에 같은 프로덕션 오그에 연동해 작업할 때의 브랜치/커밋/배포 규칙. 팀원 간 덮어쓰기 사고 방지용, 배포 전 반드시 확인

이 두 문서를 읽지 않고 작업하면 기존 구조와 충돌할 수 있으니, **반드시 먼저 읽고 이해했다고 확인해줘.**

---

## 기술 스택 요약

| 항목 | 내용 |
|---|---|
| 플랫폼 | Salesforce (Lightning Console App) |
| API 버전 | 67.0 (Winter '25) |
| 프론트엔드 | Lightning Web Components (LWC) |
| 백엔드 | Apex |
| 자동화 | Flow (Screen Flow, Autolaunched Flow, Orchestrator) |
| AI | Agentforce (OT_Service_Agent) + MIAW 채팅 |
| 외부 연동 | Slack, IoT Platform Event |

---

## 협업 규칙

### 코드 작성 시
- **기존 컴포넌트 재활용 우선**: HANDOFF.md의 LWC/Apex 목록을 먼저 확인하고, 있으면 신규 생성 대신 재사용
- **CSS 변수 준수**: PORTAL_DESIGN_PLAN.md의 `--ot-*` 변수만 사용
- **with sharing 필수**: Apex는 반드시 `with sharing` 선언
- **한국어 UI**: 포털 사용자 대상 텍스트는 한국어

### 배포 관련
- **Prod 직접 작업** — 샌드박스 없음. 배포 전 dry-run 필수
- **PR → main** 방식. 직접 main 푸시 금지
- 브랜치명 규칙: `feature-[이니셜]-[번호]` (예: `feature-HJ-3`)
- 상세 규칙(선택적 커밋, 범위 지정 배포/retrieve, PR 전 rebase, 충돌 방지 등): `GIT_WORKFLOW_RULES.md` 참조

### 커뮤니케이션
- 작업 시작 전: 무엇을 어떻게 할지 먼저 설명하고 확인받기
- 여러 파일에 걸친 변경: 변경 목록 미리 제시 후 진행
- 모르는 부분: 추측으로 진행하지 말고 질문하기

---

## 현재 우선 작업: 고객 포털 고도화

**현재 상태**: 하드코딩 + 기본 리스트 UI

**목표 상태**: 대시보드형 포털 (사이드바 네비, KPI 카드, 실시간 장비 상태, 알림)

**단계**:
```
Phase 1 — 좌측 사이드바 네비게이션으로 레이아웃 전환  ← 지금 여기
Phase 2 — 개요(Overview) 대시보드 첫 화면 추가
Phase 3 — 자산 카드 리치화, 스켈레톤 로딩, 상태 배지 통일
```

**진입점 파일**: `force-app/main/default/lwc/otAssetPortal/`

---

## 첫 번째 할 일

1. `HANDOFF.md`와 `PORTAL_DESIGN_PLAN.md`를 읽고 이해했다고 확인해줘
2. 현재 `otAssetPortal` 컴포넌트 코드를 읽고 현황을 파악해줘
3. Phase 1 작업 계획(어떤 파일을 어떻게 바꿀지)을 제시해줘
4. 내가 승인하면 구현 시작

---

## 참고: 발표 데모 시나리오 (이것만큼은 반드시 완벽히 동작)

```
고객 포털 AI 채팅 → 케이스 생성 → 담당자 배정 → Slack 알림 →
현장 수리 완료 → 포털에서 케이스 상태 확인
```

이 흐름에 영향을 주는 코드 변경 시 반드시 사전에 알려줘.

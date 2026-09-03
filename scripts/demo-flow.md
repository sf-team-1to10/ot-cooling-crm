# OT Cooling CRM Demo Flow

> Record Page Custom Tab 구조 기준 데모 동선 (2026-09-02)

---

## Scene 1: Case 접수 + 고객 파악

```
Console Home
  └─ Case 레코드 클릭 (예: 00001042)
      └─ Case Record Page 열림
          ├─ [Detail] 탭 (기본 활성)
          │    → t5CaseHeader: Path 바 (0 접수 활성) + 하이라이트 스트립
          │    → Case 번호 · Asset · Agent 최초 응답 · 상담사 인수 · SLA 확인
          │    → "출동 브리핑 생성" 버튼 클릭 → Flow 모달 실행 → 완료 Toast
          │
          └─ [Detail] 탭 필드 영역에서 Account lookup 링크 클릭 → 새 콘솔 탭
              └─ Account 360 Record Page
                  └─ [고객 현황] 탭 클릭
                       → 프로필 카드 (담당자 이름 · 이메일 · 전화 · 주소)
                       → KPI 4칸: CSAT 96 | 응답 SLA 30분 | 계약 유형 | 계약 상태
                       → 하단 내부 탭: 계약 정보 → 제품 이력 → 문제 이력 → Sales History
```

---

## Scene 2: 출동 브리핑 검토 + Priority 승인

```
Case 콘솔 탭으로 돌아감
  └─ [출동 준비] 탭 클릭
       → otDispatchBriefingWorkbench 렌더
       → 하이라이트: Priority 제안 배지 + SLA 잔여 + 산정 시각 + 비교 대상
       │
       ├─ 중앙 2/3
       │    ├─ Priority 산정 근거 테이블 (5행: 인자 · 값 · 기여도 배지)
       │    └─ Hall A CDU 12대 비교 테이블
       │         → A-07 행 빨간 강조 (pinned 아이콘)
       │         → Revision · 현재 유량 · 기준선 대비 · 추세 · 과거 실패
       │
       ├─ 우측 1/3
       │    ├─ 우선 점검 후보 (Agent 제안 배지)
       │    ├─ 전사 유사사례 (Agent 제안 배지)
       │    └─ 실시간 Trend 게이지 (1,961 L/min · 주의 배지)
       │
       └─ "Priority 승인 · 출동 확정" 버튼 클릭
            → 배지 변경: "Priority High · 담당자 승인" (초록)
            → 버튼 변경: "출동 확정됨 · 02:45" (비활성 완료 상태)
            → 하이라이트에 승인 정보 추가
```

---

## Scene 3: 담당자 배정

```
Case Record Page
  └─ [Related] 탭 클릭 → Work Order 레코드 클릭
      └─ WO Record Page 열림 (콘솔 새 주탭)
          └─ [배정] 탭 클릭
               → otDispatchCandidates 렌더
               → 하이라이트: 필요 스킬 (CDU-1700 · 배관 체결) · 복구 SLA · 현장 위치
               │
               ├─ 중앙 2/3: 후보 3명 카드
               │    1순위 강시공  ✓CDU-1700 ✓배관체결 · 대기 중 · 03:30 도착 (초록)
               │    2순위 임수리  ✓CDU-1700 —배관체결 · 작업 중 · 04:40 도착 (주황)
               │    3순위 전배관  —CDU-1700 ✓배관체결 · 주간조  · 09:00 (SLA 초과 · 흐림)
               │
               ├─ 우측 1/3: 랭킹 근거 비교 테이블
               │    스킬 매칭 · 현재 가용 · 예상 도착 · SLA 충족 비교
               │
               └─ "강시공 확정" 버튼 클릭
                    → 1순위 카드 → 초록 picked 스타일 (배경 + 두꺼운 테두리)
                    → 하이라이트에 "배정 · 강시공 · 02:46" 추가
```

---

## Scene 4: 현장 처리 + 원인 확정

```
WO Record Page (Scene 3에서 이어서)
          │
          ├─ [현장 측정] 탭 클릭
          │    → t5MeasurementTab: F-07 측정 데이터 확인
          │
          └─ [현장 확인] 탭 클릭
               → otCauseConfirm 렌더
               → 하이라이트: Asset · Revision · 최초 불합격값 · 재시험 합격값
               │
               ├─ 타임라인 카드: 가설이 원인으로 확정된 경로
               │    → 각 노드: 시각 · 이벤트 · 상세 (hit/ok 점 색상)
               │    → "현장 측정으로 확정" 배지 (보라 · 사람 통제)
               │
               └─ "Problem 생성 · RCA 기록" 버튼 클릭
                    → 버튼 → "Problem 생성됨" (비활성 완료 상태)
                    → "RCA 검토 →" 버튼 표시
```

---

## Scene 5: RCA + 시정·예방 + 갱신 검토

```
WO Record Page [Related] 탭 → Problem 레코드 클릭
  └─ Problem Record Page 열림 (콘솔 새 주탭)
      │
      ├─ [원인 분석] 탭 클릭
      │    → otProblemRca 렌더
      │    → 하이라이트: Problem 번호 · Case 번호 · 현장 근거 · 저장 시 실행 Flow
      │    │
      │    ├─ 원인 구분 카드 (담당자 확정 배지)
      │    │    → 직접 원인 (빨강 콜아웃): 배관 재조임 불합격 → 합격
      │    │    → 근본원인 (주황 콜아웃): 조직 차원 점검 기준 누락
      │    │
      │    ├─ 특수 조건 vs 공통 조건 비교 테이블 (Agent 제안 배지)
      │    │    → A-07 특수 조건 → 시정조치 N건
      │    │    → 12대 공통 조건 → 예방확인 N건
      │    │
      │    └─ "RCA·범위 확정 저장" 버튼 클릭
      │         → 시정·예방 탭으로 전환 안내
      │
      └─ [시정·예방] 탭 클릭
           → otActionResults 렌더
           → 하이라이트: 시정 N건 · 예방 N건 · 합계 N건
           │
           ├─ 중앙 2/3
           │    ├─ 생성된 Work Order 목록 (PRI_ Flow 배지)
           │    │    → 각 WO: 시정/예방 배지 + WO 번호 + Subject
           │    │
           │    └─ 점검표 개정 테이블
           │         → Rev.2 → Rev.3 비교
           │         → 신규 추가 항목 초록 배지
           │
           └─ 우측 1/3: Knowledge 초안 카드 (Agent 제안 배지)
                → 근거 · 원기록 · 측정 · 공개 범위
                → "등록 검토" / "보류" 버튼
                → "자동으로 게시하지 않습니다" 안내문

--- 갱신 검토 전환 ---

Console Navigation에서 ServiceContract 탭 클릭
  └─ SC 리스트뷰 → 계약 레코드 클릭
      └─ ServiceContract Record Page 열림
          │
          ├─ [갱신 검토] 탭 클릭
          │    → otRenewalTasks 렌더
          │    → 알림 배너: 계약 갱신 검토 구간 진입 · D-61
          │    → 하이라이트: Renewal Flow 생성 · 2026-07-31
          │    │
          │    ├─ My Tasks 카드 (3건)
          │    │    → "아이온데이터 유지보수 계약 갱신 검토" 클릭
          │    │    → 우측에 Task 상세 패널 표시
          │    │
          │    └─ 내부 [Service Contract] 탭 클릭
          │         → 계약 정보 + 서비스 운영 성과
          │         → "갱신 Opportunity 생성" 버튼 클릭
          │              → 초록 콜아웃: "갱신 Opportunity가 생성되었습니다"
          │              → 버튼 → "갱신 Opportunity 생성됨" (완료)
          │
          └─ [운영 성과] 탭 클릭
               → otServiceContractReview 렌더
               → 계약 정보 + 서비스 운영 성과 (앞 장면 데이터 배지)
               → 우측: 추가 성장 신호 (Hall B 확장 문의)
```

---

## 전체 네비게이션 맵

```
Console Home
  │
  ├─ Case Record Page
  │    ├─ [Detail]      t5CaseHeader + 케이스 정보 필드
  │    ├─ [출동 준비]    otDispatchBriefingWorkbench
  │    └─ [Related]     → WO / Problem 레코드 이동
  │
  ├─ Account 360 Record Page (Case Detail의 Account lookup 클릭)
  │    ├─ [Detail]      고객 기본 정보
  │    └─ [고객 현황]    t5Customer360
  │
  ├─ WO Record Page (Case Related에서 WO 클릭)
  │    ├─ [Detail]      작업 정보
  │    ├─ [배정]        otDispatchCandidates
  │    ├─ [현장 측정]    t5MeasurementTab
  │    ├─ [현장 확인]    otCauseConfirm
  │    └─ [Related]     → Problem 이동
  │
  ├─ Problem Record Page (WO Related에서 Problem 클릭)
  │    ├─ [Detail]      문제 기본 정보
  │    ├─ [원인 분석]    otProblemRca
  │    ├─ [시정·예방]    otActionResults
  │    └─ [Related]
  │
  └─ ServiceContract Record Page (Console Nav에서 SC 탭 클릭)
       ├─ [Detail]      계약 정보
       ├─ [갱신 검토]    otRenewalTasks
       ├─ [운영 성과]    otServiceContractReview
       └─ [Related]
```

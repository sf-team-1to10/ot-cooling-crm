# Step 5·6 수작업 가이드 — FlexiPage 필드 재배치 + 표준 Path 도입

이 가이드는 **App Builder GUI에서 직접** 진행합니다. XML을 코드로 만지지 마세요 — 파일 크기 1,800줄에 regions/facets 참조가 얽혀 있어서 손으로 편집하면 배포 실패 위험이 큽니다.

Step 1~4, 7~9는 이미 코드로 완료·커밑됨. 이 가이드의 Step 5·6이 끝나면 Step 10(최종 배포)로.

---

## 사전 준비

1. 브라우저에서 prod org 로그인.
2. Setup → Object Manager 열어두기.
3. 각 오브젝트의 **Status picklist 실제 값** 먼저 확인:
   - Case → Fields & Relationships → Status → 활성 값 목록 스크린샷/메모
   - Problem, WorkOrder, ServiceContract도 동일
4. 이 값이 아래 Step 6 표의 라벨과 다르면 **org 실제값을 우선**하고, 라벨은 Path Settings에서 재정의.

---

## Step 5. FlexiPage 필드 재배치

### 원칙

- **dynamicHighlights (Header)**: 신원 · 상태 · 핵심 KPI 3~5개
- **Detail 탭 fieldSection**: 정형 속성 (CRUD 대상)
- **커스텀 탭**: 프로세스·측정치·시각화 (Detail로 표현 어려운 것만)
- 같은 필드는 **한 곳에만** 표시.

### 편집 방법

각 FlexiPage에 대해 반복:

1. Setup → **Lightning App Builder** → 편집 대상 FlexiPage 열기 (또는 Record Page에서 톱니바퀴 → Edit Page)
2. 아래 5-1~5-5 명세대로 dynamicHighlights의 필드, Detail 탭 fieldSection의 필드, 커스텀 탭 컴포넌트를 조정
3. **Save** → **Activation** (필요 시 프로파일별 재활성화)
4. 다음 FlexiPage로 진행 (일괄 아님)

각 FlexiPage 편집 후 **로컬에 retrieve**:
```bash
sf project retrieve start -o prod -m FlexiPage:Case_Record_Page
sf project retrieve start -o prod -m FlexiPage:OT_Account_360
sf project retrieve start -o prod -m FlexiPage:WorkOrder_Record_Page
sf project retrieve start -o prod -m FlexiPage:Problem_Record_Page
sf project retrieve start -o prod -m FlexiPage:ServiceContract_Record_Page
```
retrieve로 로컬 XML 갱신 후 각 FlexiPage 단위로 커밑:
```
refactor(ui): Case Record Page 필드 재배치, 중복 헤더 제거
```

---

### 5-1. Case Record Page

**dynamicHighlights**
- CaseNumber
- Status
- Priority
- Account.Name
- Asset.Name
- CreatedDate

**Detail 탭 fieldSection**
- Subject
- Description
- Origin
- Type
- ContactId
- OwnerId
- ClosedDate
- (커스텀 필드가 org에 존재하는 경우) SLA_Deadline__c, Warranty_Status__c

**출동 준비 탭 (otDispatchBriefingWorkbench)**
- 컴포넌트 내부의 `<div class="hl-case-number">` 또는 case 번호/status를 반복 표시하는 hero 스트립 있으면 삭제.
- App Builder 편집만으로는 컴포넌트 내부 HTML을 못 바꿈. **VS Code에서** `force-app/main/default/lwc/otDispatchBriefingWorkbench/otDispatchBriefingWorkbench.html`을 열어 상단 15~30줄 검토 후 identity 반복 요소 삭제.
- 어느 요소를 삭제할지 판단 기준: **dynamicHighlights가 이미 표시하는 것과 겹치면 삭제**.

**t5CaseHeader 중복 제거**
- `force-app/main/default/lwc/t5CaseHeader/t5CaseHeader.html` 열어서 케이스 번호·Status·Priority 카드 블록(보통 `slds-page-header` 또는 `case-highlight-strip` 클래스로 감싸져 있음) 삭제.
- 남은 것은 커스텀 Path 바 표시로만 국한 (Path는 Step 6에서 표준 컴포넌트로 대체하므로, 최종적으로 t5CaseHeader는 사실상 빈 껍데기가 되어 Case_Record_Page에서 제거 가능).

---

### 5-2. Account (OT_Account_360)

**dynamicHighlights**
- Account.Name
- Industry
- Type
- Rating
- LastActivityDate

**Detail 탭 fieldSection**
- Phone
- Website
- BillingAddress
- NumberOfEmployees
- AnnualRevenue
- OwnerId

**고객 360 탭 (t5Customer360)**
- 컴포넌트 hero의 "고객사 이름 / Industry / 연락처" 카드 블록 **삭제** (dynamicHighlights와 중복).
- 남길 것: 계약 상태 요약, 최근 사건 타임라인, 자산 요약(장비 대수·평균 가동률), NPS/CSAT 값.
- 파일: `force-app/main/default/lwc/t5Customer360/t5Customer360.html` — 첫 `<section>` 안의 identity 블록 제거 후 KPI/타임라인 섹션을 상단으로.

---

### 5-3. WorkOrder Record Page

**dynamicHighlights**
- WorkOrderNumber
- Status
- Priority
- AccountId
- AssetId
- ServiceAppointment 시각 (필드가 존재한다면; 없으면 StartDate)

**Detail 탭 fieldSection**
- Subject
- Description
- StartDate
- EndDate
- OwnerId
- WorkTypeId
- (org에 있는 경우) Dispatch_Reason__c, On_Site_Result__c

**otRecordBanner + otStatusBadge**
- Detail 탭 상단에 이 두 컴포넌트가 배치되어 있으면 **하나만 유지**.
- **otStatusBadge 제거** — dynamicHighlights의 Status와 중복.
- otRecordBanner는 부수 정보(예: 다음 액션 안내)만 남기고 Status 표시부는 삭제.

**otDispatchCandidates / t5MeasurementTab / otCauseConfirm**
- 각 컴포넌트 상단의 "WO 번호 · Status" 스트립 삭제. 각 파일 html 상단 검토.

---

### 5-4. Problem Record Page

**dynamicHighlights**
- Name (Problem 번호)
- Status
- Priority
- Category (필드가 있다면)
- AffectedAssetCount (필드가 있다면; 없으면 생략)
- OwnerId

**Detail 탭 fieldSection**
- Description
- RootCause
- Resolution
- Impact
- CreatedDate
- ClosedDate

**원인 분석 탭 (otProblemRca)**
- Problem 이름/상태를 컴포넌트 상단에 반복 표시하지 말 것. 원인 후보 리스트·확정 타임라인·근거만.
- 파일: `otProblemRca/otProblemRca.html` — 상단 identity 스트립 제거.

**시정·예방 탭 (otActionResults)**
- 하이라이트 카드에서 Problem 번호를 큰 텍스트로 반복 표시하지 말 것. (Step 2에서 eyebrow는 이미 "후속 조치 · Problem {problemNumber}"로 축소됨.)

---

### 5-5. ServiceContract Record Page

**dynamicHighlights**
- ContractNumber
- Status
- StartDate
- EndDate
- AccountId
- ContractTerm

**Detail 탭 fieldSection**
- Description
- BillingFrequency
- OwnerId
- ActivatedDate
- (org에 있는 경우) Renewal_Risk__c, SLA_Level__c

**갱신 탭 (otRenewalTasks)**: 컨트랙트 번호/기간 반복 표시 삭제.
**성과 리뷰 탭 (otServiceContractReview)**: KPI 카드 그리드만 남기고 identity 반복 삭제.

---

## Step 6. 표준 Path 컴포넌트 도입

### 사전 작업 — Path Settings

Setup → **Path Settings** (검색창 "Path Settings")

각 오브젝트에 대해 **"New Path"** 클릭:

1. **Path Name**: 예 `Case Path`
2. **API Reference Name**: 자동 채워짐 (Case_Path)
3. **Object**: Case
4. **Record Type**: (사용 중인 것 선택; 없으면 Master)
5. **Picklist**: Status
6. **Next** → **Enable** 활성화

Path Setting 생성 후 편집 화면:
- 각 단계별 **Fields**: 그 단계에서 채워야 할 필드 최대 5개 지정.
- **Guidance for Success**: **빈칸 유지** (UI에 설명 문장 넣지 않는 원칙).

### 6-1. Case Path

Picklist: **Case.Status**

단계 (실제 picklist 값에 맞춰 조정. 아래는 표준 Case Status 예시):
| 순서 | Status 값 | 라벨 (Path Settings에서 재정의) |
|---|---|---|
| 1 | New | 접수 |
| 2 | In Progress / Working | 브리핑 |
| 3 | Escalated / Dispatched | 출동 |
| 4 | On Hold | (필요 없으면 skip) |
| 5 | Closed | 종료 |

> **주의**: org의 실제 picklist에 없는 값은 Path에 노출 안 됨. 필요한 값이 없으면 먼저 picklist에 추가해야 함(Object Manager → Case → Fields → Status → New).

**FlexiPage에 배치**:
- Lightning App Builder → Case Record Page 편집
- 좌측 컴포넌트 팔레트 → **Path**
- 위치: **dynamicHighlights 바로 아래**, Detail 탭 fieldSection 위
- 저장 → 활성화

### 6-2. Problem Path

Picklist: **Problem.Status** (커스텀 오브젝트라면 `Status__c`)

| 순서 | 값 | 라벨 |
|---|---|---|
| 1 | New | 발견 |
| 2 | Analyzing | 원인 분석 |
| 3 | RootCauseIdentified | 원인 확정 |
| 4 | ActionPlanned | 시정 계획 |
| 5 | Preventive | 예방 조치 |
| 6 | Closed | 종료 |

### 6-3. WorkOrder Path

Picklist: **WorkOrder.Status**

| 순서 | 값 | 라벨 |
|---|---|---|
| 1 | New | 접수 |
| 2 | Dispatched | 배정 완료 |
| 3 | On Site | 현장 도착 |
| 4 | Measurement | 측정 중 |
| 5 | Repair | 조치 중 |
| 6 | Completed | 완료 |

### 6-4. ServiceContract Path

Picklist: **ServiceContract.Status**

| 순서 | 값 | 라벨 |
|---|---|---|
| 1 | Draft | 초안 |
| 2 | Activated | 운영 중 |
| 3 | RenewalReview | 갱신 검토 |
| 4 | RenewalNegotiation | 갱신 협상 |
| 5 | Renewed / Expired | 갱신 완료 / 종료 |

### 6-5. Account

Path 불필요. Rating이 dynamicHighlights에 있으므로 별도 프로세스 표시 없음.

### otCasePath 제거

Step 6가 끝나면 `otCasePath` 커스텀 컴포넌트가 Case_Record_Page에서만 참조되고 있을 것. 표준 Path로 대체됐으므로 **FlexiPage에서 otCasePath 참조만 제거**. 컴포넌트 파일 자체는 삭제하지 말고 남겨두기 (다른 시나리오용 재활용 여지).

---

## Step 5·6 검증

각 Record Page 열어서 순서대로:

1. **/lightning/r/Case/{Id}/view**
   - dynamicHighlights → **Path (6단계)** → Detail 탭 (fieldSection) → 브리핑 탭 → Related
   - 케이스 번호가 dynamicHighlights와 커스텀 컴포넌트에 **중복 표시되지 않음**
2. **/lightning/r/Account/{Id}/view**
   - dynamicHighlights → Detail → 고객 360 → Related
   - t5Customer360 hero에 고객 이름/Industry 반복 없음
3. **/lightning/r/WorkOrder/{Id}/view**
   - Path 6단계 표시, 4개 커스텀 탭 순회 시 각 탭 콘텐츠가 자기 관심사에만 집중
4. **/lightning/r/Problem/{Id}/view**
   - Path 6단계, 원인 분석 탭에 "확정" 상태 배지 (Step 3에서 이미 반영)
5. **/lightning/r/ServiceContract/{Id}/view**
   - Path 5단계, 갱신 탭·성과 리뷰 탭 identity 반복 없음

---

## 문제 대응

- **Path가 안 보임**: Path Settings에서 Enable 확인, FlexiPage에서 활성화 확인.
- **Status 값이 안 맞음**: Object Manager에서 실제 picklist 확인 후 Path Settings 재편집.
- **필드가 안 보임**: FLS (Field-Level Security) 확인. Setup → Permission Sets → 필드별 Read 권한.
- **App Builder에서 저장 실패**: 참조된 컴포넌트가 org에 배포되지 않은 상태일 수 있음. Step 1·3·4·7·8의 코드 변경분이 배포된 후 시도.

---

## 완료 후 Step 10 진행

이 가이드의 Step 5·6이 끝나면 마지막 Step 10 (전체 배포 + URL 검증)로 진행. Step 10은 별도 지시 대기.

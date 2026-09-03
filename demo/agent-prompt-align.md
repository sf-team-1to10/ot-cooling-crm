# Agent 프롬프트 — 데모 데이터 정합성 맞추기 v3

> 코딩 에이전트에게 **`데모_데이터_확정_권고안_v2` + `demo/demo-data-canon.md`** 두 개와 함께 붙여넣는다.

---

## 역할 / 목표

`데모_데이터_확정_권고안_v2`(SSOT)와 이를 데모 흐름 순으로 재정리한 `demo/demo-data-canon.md`에 맞춰,
데모에서 보이는 **모든 용어·수치·날짜**를 정합화한다.
사실상 **확정_권고안 §9 (org 정합) → §11 (실행 순서) → §12 (체크리스트)** 를 실행하는 작업이다.

## 대원칙

1. **SSOT는 `확정_권고안_v2`.** canon.md는 그 재정리본. 충돌 시 확정_권고안이 이긴다.
2. **핵심 정정 3가지 (이것부터)**
   - 포털/Asset JSON의 `71 L/min`은 **유량이 아니라 체결 토크 `71 N·m`** → 유량은 **`1,961 L/min`** (§3.2, §9.1)
   - 유량 값 6종을 역할별로 분리 (Spec 2,050 / 이온 기준선 2,100 / 허용 1,900~2,200 / 장애 1,961 / 직전 PM 1,976 / 조치 후 2,080) (§3.1)
   - 사이트명 **마이클라우드 데이터센터** 유지, 제품명 **ColdFlow CDU-1700**, CDU **12대(A-01~A-12)**, 근본원인 **F-07 체결 토크 저하** (§4, §6)
3. 값의 출처별 처리:
   - **레코드 필드에서 오는 값** → 확정_권고안 §9.4/§10.2의 "검증만/일자수정/신규생성" 구분을 그대로 따른다. **기존 WOLI 22건·PM WO·에이징 WO는 삭제·재시드 금지.**
   - **코드 리터럴/JS 상수/Apex 하드코딩** → 해당 코드 수정
   - **CDU-A-07 포털 표시값** → DB에 뭐가 있든 정본대로 보이게 **포털 코드에 하드코딩(override, `name==='CDU-A-07'` 한정)**. 다른 자산은 기존 로직 그대로.
4. **변경 금지**: 레이아웃·CSS·차트 렌더 로직·SOQL 구조·`WITH USER_MODE`·공유/권한·기존 WOLI/WO 레코드·`Judgement__c`·`Retest_Round__c` 신규 생성·확정_권고안에 없는 성과 지표(가용성%·CSAT 등) 창작.
5. 통화 KRW · 날짜 `YYYY-MM-DD` · 발표자료 `2026.08` → `2026.04`.

---

## STEP 1 — 인벤토리 (수정 전, 사람 리뷰용)

포털 / 콘솔 덱 / 세일즈 각 화면에서 화면에 보이는 값마다 한 행 → `demo/_inventory.md`:

| 화면 | 표시 항목 | 현재 값 | 출처(파일:라인 / SObject.Field / Apex / CMDT) | 분류 | 정본 값(canon §) | 조치 |
|---|---|---|---|---|---|---|

- 분류: `리터럴` / `JS상수` / `Apex하드코딩` / `Apex계산(필드)` / `wire·@AuraEnabled` / `CMDT`
- 조치: `리터럴수정` / `override(A-07 한정)` / `필드값-검증만` / `필드값-일자수정` / `필드값-신규시드` / `FLS부여` / `❓확인필요`
- **§4.4.3 필수 항목**: `Trend_Flag__c`가 Flow 실시간 계산인지 고정값 입력인지 확인해서 표에 명시. Flow면 `❓발표전결정`.

---

## STEP 2 — 고객 포털 CDU-A-07 하드코딩 + 로직 정합 (T1 = 2026-04-08)

대상: `lwc/otEquipDashboard`, `lwc/otEquipDetail`, `classes/OTEquipDashboardController.cls`
(`t5HmiAssetHome`/`t5HmiAssetDetail`, 내부 HMi 컴포넌트도 배포돼 있으면 동일)

### 2-1. `CDU_A_07_CANON` 상수 (canon §1·§2·§4.2·§4.3 그대로)
```
name:'CDU-A-07', model:'ColdFlow CDU-1700', location:'Hall A · F-07',
site:'마이클라우드 데이터센터', customer:'아이온데이터', revision:'Rev.B',
flow:  { cur:1961, prev:1976, baseline:2100, spec:2050, band:[1900,2200], unit:'L/min',
         devFromBaseline:'-139 L/min (-6.6%)', marginToLow:'61 L/min (3.2%)' },
torque:{ atFault:71, afterFix:111, spec:110, band:[99,121], unit:'N·m' },   // 71은 토크!
dp:    { value:0.31, unit:'MPa' },
trendFlag:'이상',
sparkline:[2095,2101,2090,2093,2075,2080,2060,2046,2021,1991,1976,1961],   // PM 12회
afterFix:{ flow:2080, torque:111 },
warranty:{ start:'2022-06-09', end:'2026-06-08', remainAtFault:'약 2개월' },
nextInspection:'2026-10-15',
rootCause:'F-07 체결 토크 저하 → 체결력 부족으로 인한 유량 성능 저하',
```

### 2-2. 적용
- **`otEquipDetail.js`**: wire `detail`이 CDU-A-07이면 `CDU_A_07_CANON`으로 override.
  `METRICS` 상수를 유량(1,961/1,976, band [1900,2200]) · 토크(별도 지표로 71→111) · 차압(0.31 MPa) 체계로 교체.
  `RANGES`·차트 마커 = 2026-04-08 컨텍스트, PM 12회 추이.
  `TIMELINE`·`DOCS` = canon.
  해설/`CHAT_ANALYSIS` 근본원인 → "F-07 체결 토크 저하".
- **`otEquipDashboard.js`**: ASSETS = CDU-A-01~A-12 **12대**(A-07만 이상/이상 상태), 알람·Gauge·미니차트 = `CDU_A_07_CANON`. "71" 유량 표기 제거.
- **`otEquipDetail.html`**: `customer-name="아이온데이터"`, Advisory 스트립·주요 운전 상태·서비스·보증 탭 = canon (계약 EndDate = 데모일+61, 보증 종료 2026-06-08).
- **`OTEquipDashboardController.cls`**: `siteName = '마이클라우드 데이터센터'`. A-07 필드가 정본과 다르면 Apex는 두고 LWC override.
- **`Asset.Latest_Gauges_JSON__c` (A-07)**: 확정_권고안 §9.2 값으로 세팅 —
  `currentValue:1961, previousValue:1976, deltaFromPrevious:-15, trendFlag:"이상", measurementItemCode:"유량", sparklineValues:[2095…1961]` (12개).
  → 포털 Sparkline이 배열 길이 12를 렌더링하는지 확인.
- **로직**: 유량 "이상" 판정이 canon §4.2 규칙(기준선 2,100, 하한 1,900, 조건 1~4)에서 나오게.
  기준값이 `Trend_Threshold__mdt`면 **레코드 수정 금지** → override로 강제, `_inventory.md`에 기록.
  Flow 실시간 계산 구조면 발표 일정상 **고정값 유지** (§4.4.3).

---

## STEP 3 — org 정합 (확정_권고안 §9, 레코드 규칙 준수)

| 항목 | 조치 |
|---|---|
| §9.3 Product2 | 중복 2건 정리 → 제품명 `ColdFlow CDU-1700` |
| §9.4 WOLI | 기존 22건 **유지**. 데모 프로파일(현장 사용자·서비스 에이전트)에 WOLI 6필드 FLS 부여 → 화면 재검증. `Judgement__c`/`Retest_Round__c` 생성 금지 |
| §9.5 ServiceContract 00000011 | EndDate = 데모 실행일 + 61일. `[AUTO-MATCH-TEST]` 7건 갱신 화면에서 분리 |
| §9.7 Technical_Baseline_Spec__c | 3건 → §4.2 6개 항목으로 보완, A-07 Rev.B 조회 확인 |
| §9.8 Account | 포털 Contact AccountId 확인 → `아이온데이터` 연결 → `[DEMO] 아이온데이터` 정리·비활성 |
| §9.9 | `scripts/seed_t4_07.py` 실행 금지/폐기 표시 |
| WO 00000208 | 일자 2026-04-07 → **2026-04-08** |
| 분리 | 테스트 Case, WO 00000160, `[AUTO-MATCH-TEST]` → 메인 데모 검색·AI 근거에서 제외 |

## STEP 4 — 신규 시드 (확정_권고안 §10.2의 "신규 생성"만)

Problem+RCA 1건 / A-07 시정 WO 1건 / 예방조치 WO 11건(선정 근거 필드) / 체크리스트 Rev.3 + Knowledge 1건 / Hall B 20 MW Opportunity / 갱신 Task.
메인 Case 필드 = canon §11 표. **유사 Case 7건은 생성 안 함.**

## STEP 5 — 콘솔 덱 & 세일즈 (리터럴만)

- `demo/scenario-deck.html`: 전 장면 2026-04-08, 시각 14:14→14:38→14:45→15:30→17:30→18:24,
  유량 1,961→2,080 / 토크 71→111 / Trend Flag 이상 / 근본원인 F-07 체결 토크 / 우선순위 **S2** /
  역할(박팀장=현장 리더, 강시공=출동 엔지니어)
- `lwc/otSalesContracts` 등: 아이온데이터 계약 EndDate=데모일+61, **D-61** 강조 / 갱신 Task Due=EndDate /
  운영 성과 요약 = **복구 4시간 10분·RCA 1건·예방조치 11대** (그 외 지표 만들지 말 것)
- Task/ServiceContract/Opportunity **레코드는 수정하지 않는다** → 사람이 맞출 필드를 `demo/manual-record-fields.md`로 정리

## STEP 6 — 검증 (확정_권고안 §12 체크리스트 전체)

- grep 0건: `71 L/min`(유량으로) · `수도권 AI 데이터센터` · `스트레이너` · `CDU1350`(포털) · `아이인데이터센터` · 리더역 `강시공` · `박출동`
- §12 체크리스트 16항목 대조
- CDU-A-07 외 자산 열었을 때 값 그대로 (override가 A-07 한정)
- 기존 WOLL 22건 조회됨 (삭제 안 됨)
- 시드 스크립트 2회 실행 중복 0

---

## 산출물

1. `demo/_inventory.md` — STEP 1 + `Trend_Flag__c` 구조 + CMDT 이슈
2. 코드 diff — STEP 2, 5
3. org 변경 목록 — STEP 3 (FLS·필드값·일자수정, 무엇을 왜)
4. `scripts/apex/seed_demo_canon.apex` — STEP 4 (신규 생성만, idempotent)
5. `demo/manual-record-fields.md` — 사람이 수동으로 맞출 레코드 필드
6. 검증 리포트 — STEP 6

애매하거나 정본에 없는 값은 추측 금지 → `demo/_inventory.md`에 `❓확인필요`.

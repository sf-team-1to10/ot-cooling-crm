// Phase 4b — 빠진 데모 데이터 시딩 (seed_data.csv 순서 기준)

Case c = [SELECT Id, AssetId FROM Case WHERE CaseNumber = '00001031' LIMIT 1];
Asset a07 = [SELECT Id FROM Asset WHERE Name = 'CDU-A-07' LIMIT 1];

// ── 순서 17: Case 필드 업데이트 ──
c.Symptom_Category__c = '유량저하';
c.Impact_Level__c = 'S2 중요';
c.Reported_Symptom__c = 'CDU-A-07 계통 유량 경보. 랙 입구 온도 상승 중';
c.Warranty_Decision__c = '적용';
update c;
System.debug('Case fields updated');

// ── 순서 28: Asset CDU-A-07 Revision 업데이트 ──
a07.Applied_Revision__c = 'Rev.B';
a07.Criticality__c = '중요';
update a07;
System.debug('Asset A-07 revision updated');

// ── 순서 18: 복구 WO Root_Cause_Draft__c 업데이트 ──
List<WorkOrder> repairWOs = [
    SELECT Id FROM WorkOrder
    WHERE CaseId = :c.Id AND Work_Subtype__c = '장애복구' LIMIT 1
];
if (!repairWOs.isEmpty()) {
    repairWOs[0].Root_Cause_Draft__c = 'Rev.B 재배치 구간 체결부 이완(잠정)';
    update repairWOs[0];
    System.debug('Repair WO Root_Cause_Draft updated');

    // ── 순서 18: 복구 WOLI 유량 추가 ──
    insert new WorkOrderLineItem(
        WorkOrderId = repairWOs[0].Id,
        Measurement_Point__c = '계통',
        Measurement_Item_Code__c = '유량',
        Measured_Value__c = 2080,
        Baseline_Value__c = 2100,
        Threshold_Min__c = 1900,
        Threshold_Max__c = 2200,
        Unit__c = 'L/min',
        Judgement__c = '합격'
    );
    System.debug('Repair WOLI flow added');
}

// ── 순서 12: 시운전 WOLI 유량 추가 (현재 체결토크만 있음) ──
List<WorkOrder> commWOs = [
    SELECT Id FROM WorkOrder
    WHERE AssetId = :a07.Id AND Work_Subtype__c = '시운전' LIMIT 1
];
if (!commWOs.isEmpty()) {
    // 유량 1회차 불합격
    insert new WorkOrderLineItem(
        WorkOrderId = commWOs[0].Id,
        Measurement_Point__c = '계통',
        Measurement_Item_Code__c = '유량',
        Measured_Value__c = 1880,
        Baseline_Value__c = 2050,
        Threshold_Min__c = 1900,
        Threshold_Max__c = 2200,
        Unit__c = 'L/min',
        Judgement__c = '불합격'
    );
    // 유량 2회차 합격 (재시험)
    insert new WorkOrderLineItem(
        WorkOrderId = commWOs[0].Id,
        Measurement_Point__c = '계통',
        Measurement_Item_Code__c = '유량',
        Measured_Value__c = 2100,
        Baseline_Value__c = 2050,
        Threshold_Min__c = 1900,
        Threshold_Max__c = 2200,
        Unit__c = 'L/min',
        Judgement__c = '합격',
        Retest_Round__c = 1
    );
    System.debug('Commission WOLI flow added');
}

// ── 순서 15: 예방정비 12회 유량 WOLI (12대 비교 데이터) ──
// A-07의 직전 12회 예방정비 유량 추세
List<WorkOrder> pmWOs = new List<WorkOrder>();
List<Decimal> pmFlows = new List<Decimal>{2095, 2101, 2090, 2093, 2075, 2080, 2060, 2046, 2021, 1991, 1976, 1961};
List<String> pmDates = new List<String>{'2023-06', '2023-09', '2023-12', '2024-03', '2024-06', '2024-09', '2024-12', '2025-03', '2025-06', '2025-09', '2025-12', '2026-03'};
List<String> trendFlags = new List<String>{null, null, null, null, null, null, null, null, null, '주의', '주의', '이상'};

for (Integer i = 0; i < 12; i++) {
    List<String> parts = pmDates[i].split('-');
    Integer yr = Integer.valueOf(parts[0]);
    Integer mo = Integer.valueOf(parts[1]);
    WorkOrder pmWO = new WorkOrder(
        Subject = 'CDU-A-07 ' + pmDates[i] + ' 예방정비',
        AssetId = a07.Id,
        Work_Subtype__c = '예방정비',
        Status = 'Completed',
        StartDate = Datetime.newInstance(yr, mo, 15, 9, 0, 0),
        EndDate = Datetime.newInstance(yr, mo, 15, 17, 0, 0)
    );
    pmWOs.add(pmWO);
}
insert pmWOs;

List<WorkOrderLineItem> pmWOLIs = new List<WorkOrderLineItem>();
for (Integer i = 0; i < 12; i++) {
    WorkOrderLineItem woli = new WorkOrderLineItem(
        WorkOrderId = pmWOs[i].Id,
        Measurement_Point__c = '계통',
        Measurement_Item_Code__c = '유량',
        Measured_Value__c = pmFlows[i],
        Baseline_Value__c = 2100,
        Threshold_Min__c = 1900,
        Threshold_Max__c = 2200,
        Unit__c = 'L/min',
        Judgement__c = '합격'
    );
    if (trendFlags[i] != null) {
        woli.Trend_Flag__c = trendFlags[i];
    }
    pmWOLIs.add(woli);
}
insert pmWOLIs;
System.debug('PM 12회 + WOLI created');

// ── 순서 16: 정밀점검 권고 Case (C360 문제이력용) ──
// 이미 시딩된 Case 확인
List<Case> existingAdvice = [SELECT Id FROM Case WHERE Subject LIKE '%정밀점검%' AND Asset.Name = 'CDU-A-07' LIMIT 1];
if (existingAdvice.isEmpty()) {
    insert new Case(
        Subject = '유량 추세 확인 필요 — 정밀점검 권고',
        Status = 'New',
        AccountId = c.AccountId,
        AssetId = a07.Id,
        Symptom_Category__c = '유량저하',
        Reported_Symptom__c = '10회차 예방정비에서 기준선 대비 5.2% 하락 감지'
    );
    System.debug('Advisory case created');
}

System.debug('=== SEED PHASE 4B COMPLETE ===');

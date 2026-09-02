// Phase 4 — 데모 데이터 시딩: Case 00001031 + Problem + WorkOrder + WOLI

// 1. Case 업데이트
Case c = [SELECT Id FROM Case WHERE CaseNumber = '00001031' LIMIT 1];
Problem p = [SELECT Id FROM Problem WHERE ProblemNumber = 'PRB-000000001' LIMIT 1];

c.Agent_First_Response_At__c = Datetime.newInstance(2026, 4, 8, 2, 14, 0);
c.Agent_Handoff_At__c = Datetime.newInstance(2026, 4, 8, 2, 38, 0);
c.Problem__c = p.Id;
c.Status = 'Working';
c.Subject = 'CDU-A-07 유량 저하';
update c;
System.debug('Case updated');

// 2. Problem 업데이트
p.Subject = 'A-07만 고치면 끝인가';
p.Workaround = 'F-07 재조임 후 111 N·m 합격, 유량 2,080 정상화';
update p;
System.debug('Problem updated');

// 3. 시정조치 WO 1건
Asset ast = [SELECT Id FROM Asset WHERE Name = 'CDU-A-07' LIMIT 1];
WorkOrder woCorrective = new WorkOrder(
    Subject = 'CDU-A-07 F-07 재점검',
    CaseId = c.Id,
    AssetId = ast.Id,
    Problem__c = p.Id,
    Work_Subtype__c = '시정조치',
    Status = 'New',
    StartDate = Datetime.newInstance(2026, 4, 15, 9, 0, 0)
);
insert woCorrective;

// 4. 예방정비 WO 11건
List<WorkOrder> prevWOs = new List<WorkOrder>();
for (Integer i = 1; i <= 12; i++) {
    if (i == 7) continue; // A-07은 시정으로 생성
    String num = String.valueOf(i).leftPad(2, '0');
    prevWOs.add(new WorkOrder(
        Subject = 'CDU-A-' + num + ' 변경 구간 체결 상태 점검',
        CaseId = c.Id,
        Problem__c = p.Id,
        Work_Subtype__c = '예방정비',
        Status = 'New',
        StartDate = Datetime.newInstance(2026, 4, 22, 9, 0, 0)
    ));
}
insert prevWOs;
System.debug('WO corrective + ' + prevWOs.size() + ' preventive created');

// 5. 장애복구 WO + WOLI (원인확정 타임라인용)
WorkOrder woRepair = new WorkOrder(
    Subject = 'CDU-A-07 F-07 체결 상태 저하 복구',
    CaseId = c.Id,
    AssetId = ast.Id,
    Work_Subtype__c = '장애복구',
    Status = 'Completed',
    StartDate = Datetime.newInstance(2026, 4, 8, 3, 30, 0),
    EndDate = Datetime.newInstance(2026, 4, 8, 6, 24, 0)
);
insert woRepair;

// WOLI — 최초 측정 불합격
insert new WorkOrderLineItem(
    WorkOrderId = woRepair.Id,
    Measurement_Point__c = 'F-07',
    Measurement_Item_Code__c = '체결토크',
    Measured_Value__c = 71,
    Baseline_Value__c = 110,
    Threshold_Min__c = 99,
    Threshold_Max__c = 121,
    Unit__c = 'N·m',
    Judgement__c = '불합격'
);

// WOLI — 재시험 합격
insert new WorkOrderLineItem(
    WorkOrderId = woRepair.Id,
    Measurement_Point__c = 'F-07',
    Measurement_Item_Code__c = '체결토크',
    Measured_Value__c = 111,
    Baseline_Value__c = 110,
    Threshold_Min__c = 99,
    Threshold_Max__c = 121,
    Unit__c = 'N·m',
    Judgement__c = '합격',
    Retest_Round__c = 1
);

// 6. 시운전 WO + WOLI (Article 근거용)
WorkOrder woComm = new WorkOrder(
    Subject = 'CDU-A-07 시운전 체결 검사 (2022)',
    AssetId = ast.Id,
    Work_Subtype__c = '시운전',
    Status = 'Completed',
    StartDate = Datetime.newInstance(2022, 2, 24, 9, 0, 0),
    EndDate = Datetime.newInstance(2022, 2, 24, 17, 0, 0)
);
insert woComm;

// WOLI — 시운전 최초 불합격
insert new WorkOrderLineItem(
    WorkOrderId = woComm.Id,
    Measurement_Point__c = 'F-07',
    Measurement_Item_Code__c = '체결토크',
    Measured_Value__c = 68,
    Baseline_Value__c = 110,
    Threshold_Min__c = 99,
    Threshold_Max__c = 121,
    Unit__c = 'N·m',
    Judgement__c = '불합격'
);

// WOLI — 시운전 재조임 합격
insert new WorkOrderLineItem(
    WorkOrderId = woComm.Id,
    Measurement_Point__c = 'F-07',
    Measurement_Item_Code__c = '체결토크',
    Measured_Value__c = 112,
    Baseline_Value__c = 110,
    Threshold_Min__c = 99,
    Threshold_Max__c = 121,
    Unit__c = 'N·m',
    Judgement__c = '합격',
    Retest_Round__c = 1
);

System.debug('=== SEED COMPLETE ===');

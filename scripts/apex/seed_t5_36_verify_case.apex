// T5-36 검증용 새 Case + WorkOrder 시딩. 프로토타입 v-briefing (00001466 · 유량저하 · CDU-A-07)
// 시나리오 그대로 담아 Slack 요약 발신이 실제 데모에 어울리도록 만든다.
Id assetId = '02ibm000003uetzAAA';       // CDU-A-07
Id accountId = '001bm00002mEtbxAAC';     // 아이온데이터
Id contactId = '003bm00001oukeFAAQ';

String subj = '유량저하 · CDU-A-07 2차측 유로 저항 · 스트레이너 폐색 의심';

String reportedSymptom = '2026-04-22 정기 진단에서 유량 1961 L/min · 기준선 2100 대비 -6.62% 저하로 판정 불합격. '
    + '2026-09-02 재확인에서 동일 저하가 재현됨. 같은 날 차압 0.29 kPa · 펌프모터 전류 11.9/12.4 A로 기준 대비 불합격, '
    + '2026-04-08 · 2026-03-15 이력에도 체결토크 71 N·m/111 N·m 몰일치 존재. 개체 고장보다는 공통 원인 가능성 시사.';

String description = '[증상 요약]\n'
    + '- 유량: 1961 L/min (기준선 2100 대비 -6.62%, 12대 중 최대 하락 폭)\n'
    + '- 차압: 0.29 kPa · 펌프모터 전류 11.9/12.4 A · 체결토크 71 N·m/111 N·m 몰일치 이력\n'
    + '- 동종 장비 대비: 측정 1961/2080 두 수치가 보고됨, 이 장비는 낮은 값에 속함\n\n'
    + '[의심 원인 (추정)]\n'
    + '1. 공용 배관·밸브 설정 또는 계통 영향으로 인한 전반적 유량 저하 가능성\n'
    + '2. 내부 차압 변화 또는 펌프 운전 상태로 인한 국부적 유량 저하 가능성\n'
    + '3. 체결토크 변동에 따른 유체 경로 영향 가능성. 위 원인은 이력과 동종 장비 비교 결과를 근거로 추정일 뿐 확정 아님.\n\n'
    + '[현장 확인 사항 (우선 점검 조치)]\n'
    + '1. 공용 배관·밸브 개도 및 계통 설정 상태 확인. 밸브 위치와 밸브군 공용 설정을 점검하라.\n'
    + '2. 차압(0.29-0.35 kPa) 및 펌프모터 전류(11.9-12.4 A) 동작상태를 동시 측정해 유량 저하와의 상관관계를 확인하라.\n'
    + '3. 체결토크 몰일치 이력(71 N·m, 111 N·m)을 확인해 주요 플랜지·연결부의 조임 상태 및 누수 여부를 육안 및 토크 재측정으로 점검하라.\n'
    + '본 브리핑은 제시이며 진단 확정이 아님. 소견 기록은 담당 엔지니어가 한다.';

Case c = new Case(
    Subject = subj,
    Description = description,
    Reported_Symptom__c = reportedSymptom,
    Status = 'New',
    Priority = 'High',
    Origin = 'Phone',
    AccountId = accountId,
    ContactId = contactId,
    AssetId = assetId,
    Stage__c = '1 진단·브리핑'
);
insert c;
Case seeded = [SELECT Id, CaseNumber FROM Case WHERE Id = :c.Id];

WorkOrder wo = new WorkOrder(
    CaseId = seeded.Id,
    AssetId = assetId,
    AccountId = accountId,
    ContactId = contactId,
    Subject = 'CDU-A-07 유량 저하 현장 점검 및 스트레이너 재정비',
    Description = '진단 브리핑 기반 우선 점검 후보 3항목 실행. 도착 후 유량·차압·전류 재측정 → 스트레이너 청소/교체 판단.',
    Priority = 'High',
    Status = 'New',
    StartDate = Datetime.now()
);
insert wo;
WorkOrder wSeeded = [SELECT Id, WorkOrderNumber FROM WorkOrder WHERE Id = :wo.Id];

System.debug('=== T5-36 검증 Case (유량저하 시나리오) 준비 완료 ===');
System.debug('CaseNumber: ' + seeded.CaseNumber);
System.debug('Case Id: ' + seeded.Id);
System.debug('WO Number: ' + wSeeded.WorkOrderNumber);
System.debug('URL: https://trailsignup-8617b18a6871a9.lightning.force.com/lightning/r/Case/' + seeded.Id + '/view');

// T5-36 데모용 WorkOrder 시딩. 데모 Case 00001467에 붙는다.
// 이미 있으면 재사용, 없으면 생성.

Id caseId = '500bm00002sqTvSAAU';
Id assetId = '02ibm000003uetzAAA';
Id accountId = '001bm00002mEtbxAAC';
Id contactId = '003bm00001oukeFAAQ';
String demoSubject = 'T5-36 데모 · A-07 CDU 2차측 유로 점검 및 스트레이너 청소';

List<WorkOrder> existing = [
    SELECT Id, WorkOrderNumber, Status
    FROM WorkOrder
    WHERE CaseId = :caseId AND Subject = :demoSubject
    ORDER BY CreatedDate DESC
    LIMIT 1
];

WorkOrder wo;
if (!existing.isEmpty()) {
    wo = existing[0];
    System.debug('기존 데모 WorkOrder 재사용: ' + wo.WorkOrderNumber + ' (' + wo.Id + ')');
} else {
    wo = new WorkOrder(
        CaseId = caseId,
        AssetId = assetId,
        AccountId = accountId,
        ContactId = contactId,
        Subject = demoSubject,
        Description = 'T5-36 데모용 WorkOrder. 담당자 배정 → 현장 출동 흐름 관찰용.',
        Priority = 'High',
        Status = 'New',
        StartDate = Datetime.now()
    );
    insert wo;
    System.debug('신규 데모 WorkOrder 생성: ' + [SELECT WorkOrderNumber FROM WorkOrder WHERE Id = :wo.Id].WorkOrderNumber + ' (' + wo.Id + ')');
}

WorkOrder seeded = [
    SELECT Id, WorkOrderNumber, Subject, Status, Priority, CaseId, Case.CaseNumber,
           Asset.Name, Account.Name, Contact.Name
    FROM WorkOrder
    WHERE Id = :wo.Id
];
System.debug('=== 데모 WorkOrder 준비 완료 ===');
System.debug('WorkOrderNumber: ' + seeded.WorkOrderNumber);
System.debug('WO Id: ' + seeded.Id);
System.debug('연결 Case: ' + seeded.Case.CaseNumber);
System.debug('Asset: ' + seeded.Asset.Name);
System.debug('Account: ' + seeded.Account.Name);
System.debug('Status: ' + seeded.Status);
System.debug('URL: https://trailsignup-8617b18a6871a9.lightning.force.com/lightning/r/WorkOrder/' + seeded.Id + '/view');

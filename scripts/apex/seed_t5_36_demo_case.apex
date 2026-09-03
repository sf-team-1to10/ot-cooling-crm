// T5-36 데모용 Case 시딩. Stage=0 접수 상태로 만들어 UI에서 Path 이동을 관찰한다.
// 자산: CDU-A-07 (아이온데이터). 이미 있으면 새로 만들지 않고 기존 데모 Case 재사용.

Id assetId = '02ibm000003uetzAAA';
Id accountId = '001bm00002mEtbxAAC';
Id contactId = '003bm00001oukeFAAQ';
String demoTag = 'T5-36 데모 · Path 이동 관찰용';

List<Case> existing = [
    SELECT Id, CaseNumber, Stage__c
    FROM Case
    WHERE Subject = :demoTag
    ORDER BY CreatedDate DESC
    LIMIT 1
];

Case c;
if (!existing.isEmpty()) {
    c = existing[0];
    // 이전 데모에서 Path가 이미 진행된 상태면 0으로 되돌린다 (다시 관찰하기 위함).
    if (c.Stage__c != '0 접수') {
        c.Stage__c = '0 접수';
        update c;
    }
    System.debug('기존 데모 Case 재사용: ' + c.CaseNumber + ' (' + c.Id + ')');
} else {
    c = new Case(
        Subject = demoTag,
        Description = 'T5-36 데모 시나리오. 출동 브리핑 생성 버튼을 누르면 Path가 0 접수 → 1 진단·브리핑으로 이동한다.',
        Status = 'New',
        Priority = 'High',
        Origin = 'Phone',
        AccountId = accountId,
        ContactId = contactId,
        AssetId = assetId,
        Stage__c = '0 접수'
    );
    insert c;
    System.debug('신규 데모 Case 생성: ' + [SELECT CaseNumber FROM Case WHERE Id = :c.Id].CaseNumber + ' (' + c.Id + ')');
}

// 결과 요약
Case seeded = [
    SELECT Id, CaseNumber, Subject, Stage__c, Asset.Name, Account.Name
    FROM Case
    WHERE Id = :c.Id
];
System.debug('=== 데모 Case 준비 완료 ===');
System.debug('CaseNumber: ' + seeded.CaseNumber);
System.debug('Case Id: ' + seeded.Id);
System.debug('Subject: ' + seeded.Subject);
System.debug('Stage: ' + seeded.Stage__c);
System.debug('Asset: ' + seeded.Asset.Name);
System.debug('Account: ' + seeded.Account.Name);
System.debug('URL: https://trailsignup-8617b18a6871a9.lightning.force.com/lightning/r/Case/' + seeded.Id + '/view');

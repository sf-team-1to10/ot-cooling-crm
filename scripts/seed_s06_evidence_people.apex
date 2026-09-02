/**
 * S-06 2차 시딩 — evidence(2022 원기록) 화면의 인물 노출.
 * CR 요청자(유신 Contact)·Rev 승인자(오도면 User), 시운전 WOLI 검사자(강시공 User)를
 * 실제 레코드에 연결한다. 화면(otAssetEvidenceHistory)은 컨트롤러가 이 값을 읽어
 * 타임라인 source에 "요청자/승인자/검사자"로 표시한다.
 *
 * 재현: sf apex run --file scripts/seed_s06_evidence_people.apex -o T0INT
 */
Id yusin = [SELECT Id FROM Contact WHERE Name = '유신' LIMIT 1].Id;              // 요청자(고객)
Id odomyeon = [SELECT Id FROM User WHERE Name = '오도면' AND IsActive = true LIMIT 1].Id;  // Rev 승인자
Id gangsigong = [SELECT Id FROM User WHERE Name = '강시공' AND IsActive = true LIMIT 1].Id; // 검사자

ChangeRequest cr = [SELECT Id FROM ChangeRequest WHERE ChangeRequestNumber = 'CHG-000000001' LIMIT 1];
cr.Requester__c = yusin;
cr.Revision_Approver__c = odomyeon;
update cr;

// 시운전 WO의 F-07 체결토크 측정(최초 68·재시험 112)에 검사자 강시공
Id commissionWoId = [
    SELECT Id FROM WorkOrder
    WHERE AssetId IN (SELECT Id FROM Asset WHERE Name = 'CDU-A-07')
      AND Work_Subtype__c = '시운전' LIMIT 1
].Id;
List<WorkOrderLineItem> lines = [
    SELECT Id FROM WorkOrderLineItem
    WHERE WorkOrderId = :commissionWoId
      AND Measurement_Item_Code__c = '체결토크'
      AND Measurement_Point__c = 'F-07'
];
for (WorkOrderLineItem l : lines) {
    l.Verified_By__c = gangsigong;
}
update lines;

System.debug('SEEDED evidence people: 요청자 유신 · 승인자 오도면 · 검사자 강시공(' + lines.size() + '건)');

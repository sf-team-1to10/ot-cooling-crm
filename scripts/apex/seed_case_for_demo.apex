// 최신 Case를 시나리오에 맞게 시딩
Case c = [SELECT Id, CaseNumber, ServiceContractId, EntitlementId,
                 Warranty_Decision__c, Coverage_Type__c, Billable__c,
                 Impact_Level__c
          FROM Case
          WHERE CaseNumber = '00001465'];

// 활성 ServiceContract 연결
c.ServiceContractId = '810bm0000PagCw5AQE';  // 아이온데이터 CDU SLA 보증 계약
// Entitlement 연결
c.EntitlementId = '550bm000013HmMAAA0';      // CDU-A-07 보증 (Active)
// 보증 판정 — 시나리오: 계약 유효, Warranty 적용, 무상
c.Warranty_Decision__c = '적용';
c.Coverage_Type__c = '연장보증';
c.Billable__c = false;
// 영향 등급 — 시나리오: 긴급 대응
c.Impact_Level__c = 'S2 중요';

update c;
System.debug('Case ' + c.CaseNumber + ' seeded: SC=' + c.ServiceContractId
    + ' Entitlement=' + c.EntitlementId
    + ' Warranty=' + c.Warranty_Decision__c
    + ' Coverage=' + c.Coverage_Type__c
    + ' Billable=' + c.Billable__c
    + ' Impact=' + c.Impact_Level__c);

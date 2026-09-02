// Phase 4c — 빈 필드 채우기

Case c = [SELECT Id FROM Case WHERE CaseNumber = '00001031' LIMIT 1];

// Warranty_Judged_At__c (출동 브리핑 산정 시각)
c.Warranty_Judged_At__c = Datetime.newInstance(2026, 4, 8, 2, 40, 0);
// Dispatch_Briefing__c (브리핑 본문 — Flow가 생성하는 값)
c.Dispatch_Briefing__c = 'CDU-A-07 계통 유량 경보 발생. 랙 입구 온도 상승 중. Rev.B 변경 구간(F-07) 체결 상태 저하 가능성. 동일 모델 과거 Case 7건 중 5건이 체결부 원인, 평균 복구 3.2시간.';
// Similar_Cases_Summary__c (유사사례 요약)
c.Similar_Cases_Summary__c = '같은 모델 과거 Case 7건 중 5건이 체결부 원인 · 평균 복구 3.2시간';
update c;
System.debug('Case briefing fields updated');

// 12대 Asset에 Latest_Trend_Flag__c / Baseline 설정
List<Asset> allCDUs = [SELECT Id, Name, Latest_Trend_Flag__c, Site_Location__c FROM Asset WHERE Name LIKE 'CDU-A-%' ORDER BY Name];
for (Asset a : allCDUs) {
    a.Site_Location__c = 'Hall A';
    if (a.Name == 'CDU-A-07') {
        a.Latest_Trend_Flag__c = '이상';
    }
}
update allCDUs;
System.debug('Asset trend flags + location updated: ' + allCDUs.size());

System.debug('=== SEED PHASE 4C COMPLETE ===');

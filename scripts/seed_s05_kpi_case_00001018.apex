/**
 * S-05 1차 KPI 시딩 — 데모 대상 Case 00001018.
 * 시나리오 v4 §2.4의 고정 KPI 시각을 데모 기준일(2026-04-08)로 시딩한다.
 * 클릭/now()가 아니라 산식 앵커라 고정값이어야 한다(설계서 §7-1).
 * 실행 유저 TZ = Asia/Seoul 기준이므로 newInstance 시각이 곧 화면 표시 시각.
 *
 * 재현: sf apex run --file scripts/seed_s05_kpi_case_00001018.apex -o T0INT
 */
Case target = [SELECT Id FROM Case WHERE CaseNumber = '00001018' LIMIT 1];

// 서정비 = Priority 승인자
Id seojeongbi = [SELECT Id FROM User WHERE Name = '서정비' AND IsActive = true LIMIT 1].Id;

target.Agent_First_Response_At__c = Datetime.newInstance(2026, 4, 8, 2, 14, 0); // Agent 최초 응답
target.Agent_Handoff_At__c = Datetime.newInstance(2026, 4, 8, 2, 38, 0);        // 상담사 인수
target.Warranty_Judged_At__c = Datetime.newInstance(2026, 4, 8, 2, 40, 0);      // Priority 산정
target.Priority_Approved_At__c = Datetime.newInstance(2026, 4, 8, 2, 45, 0);    // 출동 결정=승인
target.Priority_Approved_By__c = seojeongbi;

update target;

System.debug('SEEDED 00001018 KPI: 02:14 / 02:38 / 02:40 / 02:45 · 승인자 서정비');

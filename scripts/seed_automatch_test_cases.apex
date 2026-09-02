/**
 * [AUTO-MATCH-TEST] Case_Assign_Service_Contract 활성화 후 검증용 Case 생성 + 자동 판정.
 *
 * ⚠ 이 스크립트는 Flow가 **활성화된 뒤에** 실행한다.
 *   Flow가 비활성이면 모든 자동 연결 시나리오가 FAIL로 나오는 게 정상이다.
 *
 * 선행 조건: scripts/seed_automatch_test_data.apex 로 기초 데이터가 만들어져 있어야 한다.
 *
 * 멱등: 실행할 때마다 자기 접두사([AUTO-MATCH-TEST])를 가진 Case를 먼저 지우고 새로 만든다.
 *       따라서 여러 번 돌려도 Case 수가 늘지 않는다.
 *
 * 검증 시나리오
 *   01 사용자 직접 입력값 보존      → 미리 넣은 계약이 그대로 유지되는가
 *   02 Entitlement 직접 지정        → 그 Entitlement의 계약으로 연결되는가
 *   03 Asset 유효 Entitlement 1건   → 자동 연결되는가
 *   04 Asset 후보 2건               → 연결하지 않는가
 *   05 Entitlement 기간 만료        → 빈 값으로 남는가
 *   06 Entitlement에 계약 없음      → 빈 값으로 남는가
 *   07 계약 자체가 만료             → 빈 값으로 남는가
 *   08 Entitlement EndDate 없음     → 자동 연결되는가
 *   09 Asset 변경 후 재판정         → update 시 다시 판정되는가
 *   10 기존 S2 Entitlement 할당     → 기존 Flow가 여전히 동작하는가 (회귀)
 *   11 대량 처리(200건)             → governor limit 문제가 없는가
 *
 * 실행: sf apex run --file scripts/seed_automatch_test_cases.apex -o vscodeOrg
 * 정리: sf apex run --file scripts/cleanup_automatch_test_data.apex -o vscodeOrg
 */

final String P = '[AUTO-MATCH-TEST] ';

List<Account> accts = [SELECT Id FROM Account WHERE Name = :(P + '자동매칭 테스트 고객') LIMIT 1];
if (accts.isEmpty()) {
    System.debug(LoggingLevel.ERROR, '[AUTO-MATCH-TEST] 픽스처가 없습니다. 먼저 seed_automatch_test_data.apex 를 실행하세요.');
    return;
}
Id acctId = accts[0].Id;

Map<String, Id> assetIdByCode = new Map<String, Id>();
for (Asset a : [SELECT Id, Name FROM Asset WHERE Name LIKE '[AUTO-MATCH-TEST] %']) {
    assetIdByCode.put(a.Name.removeStart(P), a.Id);
}
Map<String, Id> scIdByCode = new Map<String, Id>();
Map<Id, String> scCodeById = new Map<Id, String>();
for (ServiceContract sc : [SELECT Id, Name FROM ServiceContract WHERE Name LIKE '[AUTO-MATCH-TEST] %']) {
    scIdByCode.put(sc.Name.removeStart(P), sc.Id);
    scCodeById.put(sc.Id, sc.Name.removeStart(P));
}
Map<String, Id> entIdByCode = new Map<String, Id>();
for (Entitlement e : [SELECT Id, Name FROM Entitlement WHERE Name LIKE '[AUTO-MATCH-TEST] %']) {
    entIdByCode.put(e.Name.removeStart(P), e.Id);
}

// 이전 실행분 제거 (멱등)
List<Case> old = [SELECT Id FROM Case WHERE Subject LIKE '[AUTO-MATCH-TEST] %'];
if (!old.isEmpty()) {
    delete old;
}

// ── 단건 시나리오 생성 ────────────────────────────────────────────────────────
// subject code => 기대 계약 코드(null이면 빈 값 기대)
Map<String, String> expected = new Map<String, String>();
List<Case> toInsert = new List<Case>();

Case c01 = new Case(
    Subject = P + '01 사용자 직접 입력값 보존',
    Status = 'New', AccountId = acctId,
    AssetId = assetIdByCode.get('ASSET-SINGLE'),
    ServiceContractId = scIdByCode.get('SC-MULTI-A')   // 사용자가 직접 넣은 값
);
toInsert.add(c01);
expected.put('01 사용자 직접 입력값 보존', 'SC-MULTI-A');

Case c02 = new Case(
    Subject = P + '02 Entitlement 직접 지정',
    Status = 'New', AccountId = acctId,
    EntitlementId = entIdByCode.get('ENT-DIRECT')       // Asset은 일부러 비운다
);
toInsert.add(c02);
expected.put('02 Entitlement 직접 지정', 'SC-DIRECT');

Case c03 = new Case(
    Subject = P + '03 Asset 유효 Entitlement 1건',
    Status = 'New', AccountId = acctId,
    AssetId = assetIdByCode.get('ASSET-SINGLE')
);
toInsert.add(c03);
expected.put('03 Asset 유효 Entitlement 1건', 'SC-SINGLE');

Case c04 = new Case(
    Subject = P + '04 Asset 후보 2건',
    Status = 'New', AccountId = acctId,
    AssetId = assetIdByCode.get('ASSET-MULTI')
);
toInsert.add(c04);
expected.put('04 Asset 후보 2건', null);

Case c05 = new Case(
    Subject = P + '05 Entitlement 기간 만료',
    Status = 'New', AccountId = acctId,
    AssetId = assetIdByCode.get('ASSET-EXPIRED-ENT')
);
toInsert.add(c05);
expected.put('05 Entitlement 기간 만료', null);

Case c06 = new Case(
    Subject = P + '06 Entitlement에 계약 없음',
    Status = 'New', AccountId = acctId,
    AssetId = assetIdByCode.get('ASSET-NO-CONTRACT')
);
toInsert.add(c06);
expected.put('06 Entitlement에 계약 없음', null);

Case c07 = new Case(
    Subject = P + '07 계약 자체가 만료',
    Status = 'New', AccountId = acctId,
    AssetId = assetIdByCode.get('ASSET-EXPIRED-SC')
);
toInsert.add(c07);
expected.put('07 계약 자체가 만료', null);

Case c08 = new Case(
    Subject = P + '08 Entitlement EndDate 없음',
    Status = 'New', AccountId = acctId,
    AssetId = assetIdByCode.get('ASSET-NO-END')
);
toInsert.add(c08);
expected.put('08 Entitlement EndDate 없음', 'SC-NO-END');

Case c09 = new Case(
    Subject = P + '09 Asset 변경 후 재판정',
    Status = 'New', AccountId = acctId,
    AssetId = assetIdByCode.get('ASSET-MULTI')          // 처음엔 후보 2건이라 연결 안 됨
);
toInsert.add(c09);
expected.put('09 Asset 변경 후 재판정', 'SC-SINGLE');    // update 후 기대값

Case c10 = new Case(
    Subject = P + '10 기존 S2 Entitlement 할당 회귀',
    Status = 'New', AccountId = acctId,
    AssetId = assetIdByCode.get('ASSET-SINGLE'),
    Impact_Level__c = 'S2 중요'                          // 기존 Flow 트리거 조건
);
toInsert.add(c10);

insert toInsert;

// 09: Asset을 유효 후보 1건짜리로 바꿔 재판정시킨다
Case c09u = new Case(Id = c09.Id, AssetId = assetIdByCode.get('ASSET-SINGLE'));
update c09u;

// ── 결과 판정 ────────────────────────────────────────────────────────────────
List<String> lines = new List<String>();
Integer pass = 0, fail = 0;

for (Case c : [
    SELECT Id, CaseNumber, Subject, AssetId, EntitlementId, ServiceContractId, Impact_Level__c
    FROM Case
    WHERE Subject LIKE '[AUTO-MATCH-TEST] %'
    ORDER BY Subject
]) {
    String code = c.Subject.removeStart(P);
    String actual = c.ServiceContractId == null ? null : scCodeById.get(c.ServiceContractId);

    if (code.startsWith('10 ')) {
        // 회귀 확인: 기존 Flow가 EntitlementId를 채웠는지만 본다
        Boolean ok = c.EntitlementId != null;
        lines.add((ok ? 'PASS  ' : 'FAIL  ') + code.rightPad(32) +
                  'EntitlementId=' + (c.EntitlementId == null ? '(빈 값)' : String.valueOf(c.EntitlementId)) +
                  '  ServiceContractId=' + (actual == null ? '(빈 값)' : actual));
        if (ok) pass++; else fail++;
        continue;
    }

    String exp = expected.get(code);
    Boolean ok = (exp == null && actual == null) || (exp != null && exp.equals(actual));
    lines.add((ok ? 'PASS  ' : 'FAIL  ') + code.rightPad(32) +
              '기대=' + (exp == null ? '(빈 값)' : exp).rightPad(14) +
              '실제=' + (actual == null ? '(빈 값)' : actual));
    if (ok) pass++; else fail++;
}

// ── 11) 대량 처리: 200건 한 번에 insert 후 governor 사용량 확인 ────────────────
Integer soqlBefore = Limits.getQueries();
Integer dmlBefore = Limits.getDmlStatements();
List<Case> bulk = new List<Case>();
for (Integer i = 0; i < 200; i++) {
    bulk.add(new Case(
        Subject = P + 'BULK-' + String.valueOf(i).leftPad(3, '0'),
        Status = 'New',
        AccountId = acctId,
        AssetId = assetIdByCode.get('ASSET-SINGLE')
    ));
}
insert bulk;
Integer soqlAfter = Limits.getQueries();
Integer dmlAfter = Limits.getDmlStatements();

Integer bulkLinked = [
    SELECT count() FROM Case
    WHERE Subject LIKE '[AUTO-MATCH-TEST] BULK-%'
      AND ServiceContractId = :scIdByCode.get('SC-SINGLE')
];
delete bulk;   // 대량 건은 남기지 않는다

lines.add('');
lines.add('11 대량 처리 200건');
lines.add('   SOQL  ' + soqlBefore + ' → ' + soqlAfter + '  (한도 ' + Limits.getLimitQueries() + ')');
lines.add('   DML   ' + dmlBefore + ' → ' + dmlAfter + '  (한도 ' + Limits.getLimitDmlStatements() + ')');
lines.add('   자동 연결된 건수: ' + bulkLinked + ' / 200  (기대 200)');
if (bulkLinked == 200) pass++; else fail++;

System.debug(LoggingLevel.ERROR, '===== AUTO-MATCH CASE VERIFICATION =====');
for (String l : lines) {
    System.debug(LoggingLevel.ERROR, l);
}
System.debug(LoggingLevel.ERROR, '===== PASS ' + pass + ' / FAIL ' + fail + ' =====');
System.debug(LoggingLevel.ERROR, 'Flow가 비활성이면 자동 연결 시나리오는 전부 FAIL이 정상입니다.');

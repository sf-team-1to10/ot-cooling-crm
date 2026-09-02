/**
 * [AUTO-MATCH-TEST] Flow 활성화 후 검증용 Case 생성 + PASS/FAIL 자동 판정.
 *
 * ⚠ 이 스크립트는 두 Flow가 **활성화된 뒤에** 실행한다.
 *   - Case_Assign_Entitlement_By_Impact (triggerOrder 10)
 *   - Case_Assign_Service_Contract      (triggerOrder 20)
 *   Flow가 비활성이면 자동 배정 시나리오가 FAIL로 나오는 게 정상이다.
 *
 * 선행 조건: scripts/seed_automatch_test_data.apex 로 기초 데이터가 만들어져 있어야 한다.
 *
 * 멱등: 실행할 때마다 자기 접두사([AUTO-MATCH-TEST])를 가진 Case를 먼저 지우고 새로 만든다.
 *       따라서 여러 번 돌려도 Case 수가 늘지 않는다.
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

Map<String, Id> assetId = new Map<String, Id>();
for (Asset a : [SELECT Id, Name FROM Asset WHERE Name LIKE '[AUTO-MATCH-TEST] %']) {
    assetId.put(a.Name.removeStart(P), a.Id);
}
Map<String, Id> scId = new Map<String, Id>();
Map<Id, String> scCode = new Map<Id, String>();
for (ServiceContract sc : [SELECT Id, Name FROM ServiceContract WHERE Name LIKE '[AUTO-MATCH-TEST] %']) {
    scId.put(sc.Name.removeStart(P), sc.Id);
    scCode.put(sc.Id, sc.Name.removeStart(P));
}
Map<String, Id> entId = new Map<String, Id>();
Map<Id, String> entCode = new Map<Id, String>();
for (Entitlement e : [SELECT Id, Name FROM Entitlement WHERE Name LIKE '[AUTO-MATCH-TEST] %']) {
    entId.put(e.Name.removeStart(P), e.Id);
    entCode.put(e.Id, e.Name.removeStart(P));
}

// 이전 실행분 제거 (멱등)
List<Case> old = [SELECT Id FROM Case WHERE Subject LIKE '[AUTO-MATCH-TEST] %'];
if (!old.isEmpty()) {
    delete old;
}

// 기대값: subject code => Entitlement 코드 / ServiceContract 코드 (null = 빈 값 기대)
Map<String, String> expEnt = new Map<String, String>();
Map<String, String> expSc = new Map<String, String>();
List<Case> toInsert = new List<Case>();

// ── 일반 Case (S2 아님 → 기존 Entitlement Flow는 트리거되지 않는다) ───────────
Case c01 = new Case(Subject = P + '01 사용자 직접 입력값 보존', Status = 'New', AccountId = acctId,
    AssetId = assetId.get('ASSET-SINGLE'), ServiceContractId = scId.get('SC-MULTI-A'));
toInsert.add(c01);
expEnt.put('01 사용자 직접 입력값 보존', null);
expSc.put('01 사용자 직접 입력값 보존', 'SC-MULTI-A');

Case c02 = new Case(Subject = P + '02 Entitlement 직접 지정', Status = 'New', AccountId = acctId,
    EntitlementId = entId.get('ENT-DIRECT'));
toInsert.add(c02);
expEnt.put('02 Entitlement 직접 지정', 'ENT-DIRECT');
expSc.put('02 Entitlement 직접 지정', 'SC-DIRECT');

Case c03 = new Case(Subject = P + '03 Asset 유효 Entitlement 1건', Status = 'New', AccountId = acctId,
    AssetId = assetId.get('ASSET-SINGLE'));
toInsert.add(c03);
expEnt.put('03 Asset 유효 Entitlement 1건', null);
expSc.put('03 Asset 유효 Entitlement 1건', 'SC-SINGLE');

Case c04 = new Case(Subject = P + '04 Asset 후보 2건', Status = 'New', AccountId = acctId,
    AssetId = assetId.get('ASSET-MULTI'));
toInsert.add(c04);
expEnt.put('04 Asset 후보 2건', null);
expSc.put('04 Asset 후보 2건', null);

Case c05 = new Case(Subject = P + '05 Entitlement 기간 만료', Status = 'New', AccountId = acctId,
    AssetId = assetId.get('ASSET-EXPIRED-ENT'));
toInsert.add(c05);
expEnt.put('05 Entitlement 기간 만료', null);
expSc.put('05 Entitlement 기간 만료', null);

Case c06 = new Case(Subject = P + '06 Entitlement에 계약 없음', Status = 'New', AccountId = acctId,
    AssetId = assetId.get('ASSET-NO-CONTRACT'));
toInsert.add(c06);
expEnt.put('06 Entitlement에 계약 없음', null);
expSc.put('06 Entitlement에 계약 없음', null);

Case c07 = new Case(Subject = P + '07 계약 자체가 만료', Status = 'New', AccountId = acctId,
    AssetId = assetId.get('ASSET-EXPIRED-SC'));
toInsert.add(c07);
expEnt.put('07 계약 자체가 만료', null);
expSc.put('07 계약 자체가 만료', null);

Case c08 = new Case(Subject = P + '08 Entitlement EndDate 없음', Status = 'New', AccountId = acctId,
    AssetId = assetId.get('ASSET-NO-END'));
toInsert.add(c08);
expEnt.put('08 Entitlement EndDate 없음', null);
expSc.put('08 Entitlement EndDate 없음', 'SC-NO-END');

Case c09 = new Case(Subject = P + '09 Asset 변경 후 재판정', Status = 'New', AccountId = acctId,
    AssetId = assetId.get('ASSET-MULTI'));   // 처음엔 후보 2건이라 연결 안 됨
toInsert.add(c09);
expEnt.put('09 Asset 변경 후 재판정', null);
expSc.put('09 Asset 변경 후 재판정', 'SC-SINGLE');   // update 후 기대값

// ── S2 Case (기존 Entitlement Flow가 트리거된다) ─────────────────────────────
Case c10 = new Case(Subject = P + '10 S2 Asset 후보 1건', Status = 'New', AccountId = acctId,
    AssetId = assetId.get('ASSET-SINGLE'), Impact_Level__c = 'S2 중요');
toInsert.add(c10);
expEnt.put('10 S2 Asset 후보 1건', 'ENT-SINGLE');
expSc.put('10 S2 Asset 후보 1건', 'SC-SINGLE');

Case c11 = new Case(Subject = P + '11 S2 Asset 후보 2건', Status = 'New', AccountId = acctId,
    AssetId = assetId.get('ASSET-MULTI'), Impact_Level__c = 'S2 중요');
toInsert.add(c11);
expEnt.put('11 S2 Asset 후보 2건', null);
expSc.put('11 S2 Asset 후보 2건', null);

// 핵심 회귀 방지: Account에 유효 Entitlement가 여러 건이면 임의로 고르지 않는다
Case c12 = new Case(Subject = P + '12 S2 Asset 없음 Account 후보 다수', Status = 'New', AccountId = acctId,
    Impact_Level__c = 'S2 중요');
toInsert.add(c12);
expEnt.put('12 S2 Asset 없음 Account 후보 다수', null);
expSc.put('12 S2 Asset 없음 Account 후보 다수', null);

Case c13 = new Case(Subject = P + '13 S2 Entitlement 직접 지정 보존', Status = 'New', AccountId = acctId,
    EntitlementId = entId.get('ENT-DIRECT'), Impact_Level__c = 'S2 중요');
toInsert.add(c13);
expEnt.put('13 S2 Entitlement 직접 지정 보존', 'ENT-DIRECT');
expSc.put('13 S2 Entitlement 직접 지정 보존', 'SC-DIRECT');

insert toInsert;

// 09: Asset을 유효 후보 1건짜리로 바꿔 재판정시킨다
update new Case(Id = c09.Id, AssetId = assetId.get('ASSET-SINGLE'));

// ── 결과 판정 ────────────────────────────────────────────────────────────────
List<String> lines = new List<String>();
Integer pass = 0, fail = 0;

lines.add('결과  시나리오                              Entitlement                 ServiceContract');
lines.add('--------------------------------------------------------------------------------------------------');

for (Case c : [
    SELECT Id, CaseNumber, Subject, AssetId, EntitlementId, ServiceContractId, Impact_Level__c
    FROM Case
    WHERE Subject LIKE '[AUTO-MATCH-TEST] %'
    ORDER BY Subject
]) {
    String code = c.Subject.removeStart(P);
    String aEnt = c.EntitlementId == null ? null : entCode.get(c.EntitlementId);
    String aSc = c.ServiceContractId == null ? null : scCode.get(c.ServiceContractId);
    String eEnt = expEnt.get(code);
    String eSc = expSc.get(code);

    Boolean okEnt = (eEnt == null && aEnt == null) || (eEnt != null && eEnt.equals(aEnt));
    Boolean okSc = (eSc == null && aSc == null) || (eSc != null && eSc.equals(aSc));
    Boolean ok = okEnt && okSc;

    lines.add(
        (ok ? 'PASS  ' : 'FAIL  ') + code.rightPad(38) +
        ((okEnt ? '' : '✗ ') + (aEnt == null ? '(빈 값)' : aEnt) +
            (okEnt ? '' : ' (기대 ' + (eEnt == null ? '빈 값' : eEnt) + ')')).rightPad(28) +
        (okSc ? '' : '✗ ') + (aSc == null ? '(빈 값)' : aSc) +
            (okSc ? '' : ' (기대 ' + (eSc == null ? '빈 값' : eSc) + ')')
    );
    if (ok) pass++; else fail++;
}

// ── 14) 대량 처리: 200건 한 번에 insert 후 governor 사용량 확인 ───────────────
Integer soqlBefore = Limits.getQueries();
Integer dmlBefore = Limits.getDmlStatements();
List<Case> bulk = new List<Case>();
for (Integer i = 0; i < 200; i++) {
    bulk.add(new Case(
        Subject = P + 'BULK-' + String.valueOf(i).leftPad(3, '0'),
        Status = 'New',
        AccountId = acctId,
        AssetId = assetId.get('ASSET-SINGLE'),
        Impact_Level__c = 'S2 중요'      // 두 Flow를 모두 태운다
    ));
}
insert bulk;
Integer soqlAfter = Limits.getQueries();
Integer dmlAfter = Limits.getDmlStatements();

Integer bulkLinked = [
    SELECT count() FROM Case
    WHERE Subject LIKE '[AUTO-MATCH-TEST] BULK-%'
      AND EntitlementId = :entId.get('ENT-SINGLE')
      AND ServiceContractId = :scId.get('SC-SINGLE')
];
delete bulk;   // 대량 건은 남기지 않는다

lines.add('');
lines.add('14 대량 처리 200건 (S2 + Asset, 두 Flow 모두 실행)');
lines.add('   SOQL  ' + soqlBefore + ' → ' + soqlAfter + '  (한도 ' + Limits.getLimitQueries() + ')');
lines.add('   DML   ' + dmlBefore + ' → ' + dmlAfter + '  (한도 ' + Limits.getLimitDmlStatements() + ')');
lines.add('   ENT-SINGLE + SC-SINGLE 로 배정된 건수: ' + bulkLinked + ' / 200  (기대 200)');
if (bulkLinked == 200) { pass++; } else { fail++; }

System.debug(LoggingLevel.ERROR, '===== AUTO-MATCH CASE VERIFICATION =====');
for (String l : lines) {
    System.debug(LoggingLevel.ERROR, l);
}
System.debug(LoggingLevel.ERROR, '===== PASS ' + pass + ' / FAIL ' + fail + ' =====');
System.debug(LoggingLevel.ERROR, 'Flow가 비활성이면 자동 배정 시나리오는 FAIL이 정상입니다.');

/**
 * [AUTO-MATCH-TEST] Case Entitlement·Service Contract 자동 배정 규칙 드라이런 검증.
 *
 * Flow를 배포/활성화하지 않은 상태에서도 두 Flow의 판정이 의도대로 나오는지 확인하기 위해,
 * Flow가 수행하는 것과 동일한 조회 조건을 SOQL로 재현해 시나리오별 결과를 출력한다.
 *
 * 읽기 전용이다. DML을 전혀 하지 않는다.
 *
 * 재현 대상
 *   A. Case_Assign_Entitlement_By_Impact (triggerOrder 10, S2 Case 생성 시)
 *        진입: Impact_Level__c='S2 중요' AND EntitlementId IsNull
 *        후보: Entitlement.AccountId = Case.AccountId
 *              AND StartDate <= TODAY AND (EndDate = null OR EndDate >= TODAY)
 *              AND (Case.AssetId 없음  OR  Entitlement.AssetId = Case.AssetId)
 *        정확히 1건일 때만 EntitlementId 할당. 0건·2건 이상이면 비워 둠.
 *
 *   B. Case_Assign_Service_Contract (triggerOrder 20)
 *        진입: ServiceContractId IsNull
 *        1) EntitlementId 있음 → 그 Entitlement(계약 존재 + 날짜 유효) → 그 계약(날짜 유효) → 연결
 *        2) EntitlementId 없음 + AssetId·AccountId 있음 → Asset 정확 일치 유효 후보
 *           → 정확히 1건일 때만, 그 계약의 날짜 유효성까지 확인 후 연결
 *
 * Entitlement.Status / ServiceContract.Status는 파생 필드라 쓰지 않고 날짜로 판정한다.
 *
 * 실행: sf apex run --file scripts/verify_automatch_rules.apex -o vscodeOrg
 */

final String P = '[AUTO-MATCH-TEST] ';

List<Account> accts = [SELECT Id FROM Account WHERE Name = :(P + '자동매칭 테스트 고객') LIMIT 1];
if (accts.isEmpty()) {
    System.debug(LoggingLevel.ERROR, '[AUTO-MATCH-TEST] 픽스처가 없습니다. 먼저 seed_automatch_test_data.apex 를 실행하세요.');
    return;
}
Id acctId = accts[0].Id;

Map<Id, String> scNameById = new Map<Id, String>();
Set<Id> validScIds = new Set<Id>();
for (ServiceContract sc : [
    SELECT Id, Name, StartDate, EndDate FROM ServiceContract WHERE Name LIKE '[AUTO-MATCH-TEST] %'
]) {
    scNameById.put(sc.Id, sc.Name.removeStart(P));
}
for (ServiceContract sc : [
    SELECT Id FROM ServiceContract
    WHERE Name LIKE '[AUTO-MATCH-TEST] %'
      AND StartDate <= TODAY
      AND (EndDate = null OR EndDate >= TODAY)
]) {
    validScIds.add(sc.Id);
}
Map<Id, String> entNameById = new Map<Id, String>();
for (Entitlement e : [SELECT Id, Name FROM Entitlement WHERE Name LIKE '[AUTO-MATCH-TEST] %']) {
    entNameById.put(e.Id, e.Name.removeStart(P));
}

// Account 기준 유효 Entitlement 전체 (기존 Flow의 Get_Valid_Entitlements와 동일 조건)
List<Entitlement> accountValid = [
    SELECT Id, Name, AssetId, ServiceContractId
    FROM Entitlement
    WHERE AccountId = :acctId
      AND StartDate <= TODAY
      AND (EndDate = null OR EndDate >= TODAY)
];

List<String> out = new List<String>();

// ─────────────────────────────────────────────────────────────────────────────
out.add('A. Case_Assign_Entitlement_By_Impact (S2 Case 생성) → Case_Assign_Service_Contract 연쇄');
out.add('   Account 유효 Entitlement 총 ' + accountValid.size() + '건');
out.add('');
out.add('   Case의 Asset            후보  EntitlementId          ServiceContractId');
out.add('   ---------------------------------------------------------------------------------');

// Asset 지정 케이스 + Asset 미지정 케이스
List<Id> assetScenarios = new List<Id>();
List<String> assetLabels = new List<String>();
for (Asset a : [SELECT Id, Name FROM Asset WHERE Name LIKE '[AUTO-MATCH-TEST] %' ORDER BY Name]) {
    assetScenarios.add(a.Id);
    assetLabels.add(a.Name.removeStart(P));
}
assetScenarios.add(null);
assetLabels.add('(Asset 없음)');

for (Integer i = 0; i < assetScenarios.size(); i++) {
    Id caseAssetId = assetScenarios[i];

    // 기존 Flow: Asset 일치 조건으로 후보 선별
    List<Entitlement> cands = new List<Entitlement>();
    for (Entitlement e : accountValid) {
        if (caseAssetId == null || e.AssetId == caseAssetId) {
            cands.add(e);
        }
    }

    String entOut = '(빈 값)';
    String scOut = '(빈 값)';
    Id assignedEntId = null;
    if (cands.size() == 1) {
        assignedEntId = cands[0].Id;
        entOut = entNameById.get(assignedEntId);

        // 신규 Flow 우선순위 1: 그 Entitlement의 계약이 유효하면 연결
        Id scId = cands[0].ServiceContractId;
        if (scId != null && validScIds.contains(scId)) {
            scOut = scNameById.get(scId);
        } else if (scId != null) {
            scOut = '(빈 값 · 계약 만료 ' + scNameById.get(scId) + ')';
        } else {
            scOut = '(빈 값 · 계약 미연결)';
        }
    }

    out.add('   ' + assetLabels[i].rightPad(24) + String.valueOf(cands.size()).rightPad(6) +
            entOut.rightPad(23) + scOut);
}

// ─────────────────────────────────────────────────────────────────────────────
out.add('');
out.add('B. Case_Assign_Service_Contract 단독 (EntitlementId 없는 일반 Case, Asset 기준)');
out.add('');
out.add('   Case의 Asset            후보  판정');
out.add('   ---------------------------------------------------------------------------------');

for (Asset a : [SELECT Id, Name FROM Asset WHERE Name LIKE '[AUTO-MATCH-TEST] %' ORDER BY Name]) {
    List<Entitlement> cands = [
        SELECT Id, Name, ServiceContractId
        FROM Entitlement
        WHERE AccountId = :acctId
          AND AssetId = :a.Id
          AND ServiceContractId != null
          AND StartDate <= TODAY
          AND (EndDate = null OR EndDate >= TODAY)
    ];
    String verdict;
    if (cands.size() == 0) {
        verdict = '연결 안 함 (후보 0건 → 빈 값 유지)';
    } else if (cands.size() > 1) {
        verdict = '연결 안 함 (후보 2건 이상 → 임의 선택 금지)';
    } else {
        Id scId = cands[0].ServiceContractId;
        verdict = validScIds.contains(scId)
            ? '연결 → ' + scNameById.get(scId)
            : '연결 안 함 (계약 만료: ' + scNameById.get(scId) + ')';
    }
    out.add('   ' + a.Name.removeStart(P).rightPad(24) + String.valueOf(cands.size()).rightPad(6) + verdict);
}

// ─────────────────────────────────────────────────────────────────────────────
out.add('');
out.add('C. Case_Assign_Service_Contract 우선순위 1 (EntitlementId 직접 지정)');
out.add('');
out.add('   Entitlement             판정');
out.add('   ---------------------------------------------------------------------------------');

for (Entitlement e : [
    SELECT Id, Name FROM Entitlement WHERE Name LIKE '[AUTO-MATCH-TEST] %' ORDER BY Name
]) {
    List<Entitlement> hit = [
        SELECT Id, ServiceContractId
        FROM Entitlement
        WHERE Id = :e.Id
          AND ServiceContractId != null
          AND StartDate <= TODAY
          AND (EndDate = null OR EndDate >= TODAY)
    ];
    String verdict;
    if (hit.isEmpty()) {
        verdict = '연결 안 함 (Entitlement 무효 또는 계약 미연결)';
    } else {
        Id scId = hit[0].ServiceContractId;
        verdict = validScIds.contains(scId)
            ? '연결 → ' + scNameById.get(scId)
            : '연결 안 함 (계약 만료: ' + scNameById.get(scId) + ')';
    }
    out.add('   ' + e.Name.removeStart(P).rightPad(24) + verdict);
}

System.debug(LoggingLevel.ERROR, '===== AUTO-MATCH RULE DRY-RUN (' + Date.today() + ') =====');
for (String l : out) {
    System.debug(LoggingLevel.ERROR, l);
}
System.debug(LoggingLevel.ERROR, '===== END =====');

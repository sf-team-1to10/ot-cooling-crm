/**
 * [AUTO-MATCH-TEST] Case_Assign_Service_Contract 매칭 규칙 드라이런 검증.
 *
 * Flow를 배포/활성화하지 않은 상태에서도 매칭 규칙이 의도대로 나오는지 확인하기 위해,
 * Flow가 수행하는 것과 동일한 조회 조건을 SOQL로 재현해 시나리오별 판정 결과를 출력한다.
 *
 * 읽기 전용이다. DML을 전혀 하지 않는다.
 *
 * Flow와 1:1로 대응하는 부분
 *   - 진입 조건            : Case.ServiceContractId == null
 *   - 우선순위 2 (Entitlement): Entitlement.Id = Case.EntitlementId
 *                             AND ServiceContractId != null
 *                             AND StartDate <= TODAY AND (EndDate = null OR EndDate >= TODAY)
 *                           → 그 계약이 StartDate <= TODAY AND (EndDate = null OR EndDate >= TODAY)
 *   - 우선순위 3~5 (Asset)   : Entitlement.AccountId = Case.AccountId
 *                             AND AssetId = Case.AssetId          ← 이름이 아니라 Id로 매칭
 *                             AND ServiceContractId != null
 *                             AND 날짜 유효
 *                           → 후보가 정확히 1건일 때만, 그 계약의 날짜 유효성까지 확인
 *   - Entitlement.Status / ServiceContract.Status는 파생 필드라 쓰지 않고 날짜로 판정한다.
 *     (두 조건의 결과가 동일함은 별도로 확인했다)
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

// 계약 Id → 표시용 이름
Map<Id, ServiceContract> scById = new Map<Id, ServiceContract>();
for (ServiceContract sc : [SELECT Id, Name, StartDate, EndDate FROM ServiceContract WHERE Name LIKE '[AUTO-MATCH-TEST] %']) {
    scById.put(sc.Id, sc);
}

// 날짜상 유효한 계약 Id 집합 (Flow의 계약 유효성 Get Records와 동일 조건)
Set<Id> validScIds = new Set<Id>();
for (ServiceContract sc : [
    SELECT Id FROM ServiceContract
    WHERE Name LIKE '[AUTO-MATCH-TEST] %'
      AND StartDate <= TODAY
      AND (EndDate = null OR EndDate >= TODAY)
]) {
    validScIds.add(sc.Id);
}

List<String> lines = new List<String>();
lines.add('시나리오(Asset)        경로        후보  판정');
lines.add('---------------------------------------------------------------------------');

// ── 우선순위 3~5: Asset 기준 경로 ──────────────────────────────────────────────
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
    if (cands.size() != 1) {
        verdict = (cands.size() == 0)
            ? '연결 안 함 (후보 0건 → 빈 값 유지)'
            : '연결 안 함 (후보 2건 이상 → 임의 선택 금지)';
    } else {
        Id scId = cands[0].ServiceContractId;
        verdict = validScIds.contains(scId)
            ? '연결 → ' + scById.get(scId).Name.removeStart(P)
            : '연결 안 함 (계약 만료: ' + scById.get(scId).Name.removeStart(P) + ')';
    }

    lines.add(
        a.Name.removeStart(P).rightPad(22) +
        'Asset       '.substring(0, 12) +
        String.valueOf(cands.size()).rightPad(6) +
        verdict
    );
}

// ── 우선순위 2: Entitlement 직접 지정 경로 ────────────────────────────────────
lines.add('---------------------------------------------------------------------------');
for (Entitlement e : [
    SELECT Id, Name, ServiceContractId, StartDate, EndDate
    FROM Entitlement
    WHERE Name LIKE '[AUTO-MATCH-TEST] %'
    ORDER BY Name
]) {
    // Flow의 Get_Case_Entitlement 조건 재현
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
            ? '연결 → ' + scById.get(scId).Name.removeStart(P)
            : '연결 안 함 (계약 만료: ' + scById.get(scId).Name.removeStart(P) + ')';
    }

    lines.add(
        e.Name.removeStart(P).rightPad(22) +
        'Entitlement '.substring(0, 12) +
        '-     ' +
        verdict
    );
}

System.debug(LoggingLevel.ERROR, '===== AUTO-MATCH RULE DRY-RUN (' + Date.today() + ') =====');
for (String l : lines) {
    System.debug(LoggingLevel.ERROR, l);
}
System.debug(LoggingLevel.ERROR, '===== END =====');

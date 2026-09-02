/**
 * [AUTO-MATCH-TEST] Case ↔ Service Contract 자동 매칭 검증용 기초 데이터 시드.
 *
 * 목적
 *   Case_Assign_Service_Contract Flow의 매칭 규칙(유효 Entitlement 정확히 1건일 때만 연결)을
 *   검증하기 위한 Account / Asset / ServiceContract / Entitlement 픽스처를 만든다.
 *
 * 원칙
 *   - 기존 데모 레코드는 절대 건드리지 않는다. 모든 레코드를 새로 만든다.
 *   - 모든 Name에 '[AUTO-MATCH-TEST] ' 접두사를 붙인다.
 *   - 시나리오별로 Asset을 분리한다. Entitlement는 Asset Id를 직접 참조한다(이름 조회 금지).
 *   - 멱등(idempotent): Name으로 조회 후 없으면 insert, 있으면 원하는 값으로 update 한다.
 *     여러 번 실행해도 레코드 수가 늘지 않는다.
 *   - 자동 연결을 발생시킬 테스트 Case는 여기서 만들지 않는다.
 *     Flow 활성화 이후 scripts/seed_automatch_test_cases.apex 로 별도 생성한다.
 *
 * 부작용 회피
 *   - Service_Contract_D90_Renewal_Review(스케줄 Flow)가 D-0~D-90 계약에 Task를 만든다.
 *     유효 계약은 EndDate를 today+400으로, 만료 계약은 today-120으로 두어 D-90 창을 피한다.
 *   - Asset_Warranty_On_Acceptance는 Asset Update + Service_Ready_Status__c 조건이라
 *     여기서 만드는 Asset insert로는 트리거되지 않는다.
 *
 * 실행:  sf apex run --file scripts/seed_automatch_test_data.apex -o vscodeOrg
 * 정리:  sf apex run --file scripts/cleanup_automatch_test_data.apex -o vscodeOrg
 */

final String P = '[AUTO-MATCH-TEST] ';
final Date TODAY = Date.today();
final Date FAR_PAST = TODAY.addDays(-800);
final Date PAST = TODAY.addDays(-120);
final Date RECENT = TODAY.addDays(-30);
final Date FUTURE = TODAY.addDays(365);
final Date FAR_FUTURE = TODAY.addDays(400);

List<String> report = new List<String>();

// ---------------------------------------------------------------------------
// 1) Account — 테스트 전용 고객 1건
// ---------------------------------------------------------------------------
final String ACCT_NAME = P + '자동매칭 테스트 고객';
Account acct;
List<Account> foundAccts = [SELECT Id, Name FROM Account WHERE Name = :ACCT_NAME LIMIT 1];
if (foundAccts.isEmpty()) {
    acct = new Account(Name = ACCT_NAME);
    insert acct;
    report.add('Account (created)      ' + acct.Id + '  ' + ACCT_NAME);
} else {
    acct = foundAccts[0];
    report.add('Account (reused)       ' + acct.Id + '  ' + ACCT_NAME);
}

// ---------------------------------------------------------------------------
// 2) Asset — 시나리오별로 완전히 분리한다
// ---------------------------------------------------------------------------
// key = 시나리오 코드, value = 설명
Map<String, String> assetPlan = new Map<String, String>{
    'ASSET-SINGLE'      => '유효 Entitlement 정확히 1건 → 자동 연결 기대',
    'ASSET-MULTI'       => '유효 Entitlement 2건 → 자동 연결하지 않음 기대',
    'ASSET-EXPIRED-ENT' => 'Entitlement 기간 만료 → 후보 0건, 빈 값 유지 기대',
    'ASSET-NO-CONTRACT' => 'Entitlement 유효하지만 ServiceContractId 없음 → 후보 0건 기대',
    'ASSET-EXPIRED-SC'  => 'Entitlement 유효 + 연결 계약이 만료 → 만료 계약 정책 분기 확인용',
    'ASSET-NO-END'      => 'Entitlement EndDate 비어 있음 → 유효로 취급되어 자동 연결 기대',
    'ASSET-DIRECT-ENT'  => 'Case.EntitlementId 직접 지정 경로 확인용'
};

Map<String, Asset> assetByCode = new Map<String, Asset>();
Set<String> assetNames = new Set<String>();
for (String code : assetPlan.keySet()) {
    assetNames.add(P + code);
}
Map<String, Asset> existingAssets = new Map<String, Asset>();
for (Asset a : [SELECT Id, Name, AccountId FROM Asset WHERE Name IN :assetNames]) {
    existingAssets.put(a.Name, a);
}

List<Asset> assetsToInsert = new List<Asset>();
List<Asset> assetsToUpdate = new List<Asset>();
for (String code : assetPlan.keySet()) {
    String nm = P + code;
    Asset a = existingAssets.get(nm);
    if (a == null) {
        assetsToInsert.add(new Asset(
            Name = nm,
            AccountId = acct.Id,
            Description = assetPlan.get(code),
            Status = 'Installed',
            InstallDate = RECENT
        ));
    } else {
        a.AccountId = acct.Id;
        a.Description = assetPlan.get(code);
        assetsToUpdate.add(a);
    }
}
if (!assetsToInsert.isEmpty()) insert assetsToInsert;
if (!assetsToUpdate.isEmpty()) update assetsToUpdate;

for (Asset a : [SELECT Id, Name FROM Asset WHERE Name IN :assetNames]) {
    assetByCode.put(a.Name.removeStart(P), a);
}
for (String code : assetPlan.keySet()) {
    Asset a = assetByCode.get(code);
    report.add('Asset                  ' + a.Id + '  ' + P + code);
}

// ---------------------------------------------------------------------------
// 3) ServiceContract
// ---------------------------------------------------------------------------
// code => [StartDate, EndDate]
Map<String, List<Date>> scPlan = new Map<String, List<Date>>{
    'SC-SINGLE'      => new List<Date>{ FAR_PAST, FAR_FUTURE },
    'SC-MULTI-A'     => new List<Date>{ FAR_PAST, FAR_FUTURE },
    'SC-MULTI-B'     => new List<Date>{ FAR_PAST, FAR_FUTURE },
    'SC-EXPIRED-ENT' => new List<Date>{ FAR_PAST, FAR_FUTURE },
    'SC-EXPIRED'     => new List<Date>{ FAR_PAST, PAST },
    'SC-NO-END'      => new List<Date>{ FAR_PAST, FAR_FUTURE },
    'SC-DIRECT'      => new List<Date>{ FAR_PAST, FAR_FUTURE }
};

Set<String> scNames = new Set<String>();
for (String code : scPlan.keySet()) {
    scNames.add(P + code);
}
Map<String, ServiceContract> existingScs = new Map<String, ServiceContract>();
for (ServiceContract sc : [SELECT Id, Name FROM ServiceContract WHERE Name IN :scNames]) {
    existingScs.put(sc.Name, sc);
}

List<ServiceContract> scToInsert = new List<ServiceContract>();
List<ServiceContract> scToUpdate = new List<ServiceContract>();
for (String code : scPlan.keySet()) {
    String nm = P + code;
    List<Date> range = scPlan.get(code);
    ServiceContract sc = existingScs.get(nm);
    if (sc == null) {
        scToInsert.add(new ServiceContract(
            Name = nm,
            AccountId = acct.Id,
            StartDate = range[0],
            EndDate = range[1]
        ));
    } else {
        sc.AccountId = acct.Id;
        sc.StartDate = range[0];
        sc.EndDate = range[1];
        scToUpdate.add(sc);
    }
}
if (!scToInsert.isEmpty()) insert scToInsert;
if (!scToUpdate.isEmpty()) update scToUpdate;

Map<String, ServiceContract> scByCode = new Map<String, ServiceContract>();
for (ServiceContract sc : [SELECT Id, Name, StartDate, EndDate, Status FROM ServiceContract WHERE Name IN :scNames]) {
    scByCode.put(sc.Name.removeStart(P), sc);
}
for (String code : scPlan.keySet()) {
    ServiceContract sc = scByCode.get(code);
    report.add('ServiceContract        ' + sc.Id + '  ' + P + code + '  (' + sc.StartDate + ' ~ ' + sc.EndDate + ', ' + sc.Status + ')');
}

// ---------------------------------------------------------------------------
// 4) Entitlement — Asset Id / ServiceContract Id를 직접 참조한다
// ---------------------------------------------------------------------------
// code => { assetCode, scCode(없으면 null), startDate, endDate(없으면 null) }
List<Map<String, Object>> entPlan = new List<Map<String, Object>>{
    new Map<String, Object>{ 'code' => 'ENT-SINGLE',      'asset' => 'ASSET-SINGLE',      'sc' => 'SC-SINGLE',      'start' => RECENT,   'end' => FUTURE },
    new Map<String, Object>{ 'code' => 'ENT-MULTI-A',     'asset' => 'ASSET-MULTI',       'sc' => 'SC-MULTI-A',     'start' => RECENT,   'end' => FUTURE },
    new Map<String, Object>{ 'code' => 'ENT-MULTI-B',     'asset' => 'ASSET-MULTI',       'sc' => 'SC-MULTI-B',     'start' => RECENT,   'end' => FUTURE },
    new Map<String, Object>{ 'code' => 'ENT-EXPIRED',     'asset' => 'ASSET-EXPIRED-ENT', 'sc' => 'SC-EXPIRED-ENT', 'start' => FAR_PAST, 'end' => PAST },
    new Map<String, Object>{ 'code' => 'ENT-NO-CONTRACT', 'asset' => 'ASSET-NO-CONTRACT', 'sc' => null,             'start' => RECENT,   'end' => FUTURE },
    new Map<String, Object>{ 'code' => 'ENT-EXPIRED-SC',  'asset' => 'ASSET-EXPIRED-SC',  'sc' => 'SC-EXPIRED',     'start' => RECENT,   'end' => FUTURE },
    new Map<String, Object>{ 'code' => 'ENT-NO-END',      'asset' => 'ASSET-NO-END',      'sc' => 'SC-NO-END',      'start' => RECENT,   'end' => null },
    new Map<String, Object>{ 'code' => 'ENT-DIRECT',      'asset' => 'ASSET-DIRECT-ENT',  'sc' => 'SC-DIRECT',      'start' => RECENT,   'end' => FUTURE }
};

Set<String> entNames = new Set<String>();
for (Map<String, Object> row : entPlan) {
    entNames.add(P + (String) row.get('code'));
}
Map<String, Entitlement> existingEnts = new Map<String, Entitlement>();
for (Entitlement e : [SELECT Id, Name FROM Entitlement WHERE Name IN :entNames]) {
    existingEnts.put(e.Name, e);
}

List<Entitlement> entToInsert = new List<Entitlement>();
List<Entitlement> entToUpdate = new List<Entitlement>();
for (Map<String, Object> row : entPlan) {
    String nm = P + (String) row.get('code');
    String scCode = (String) row.get('sc');
    Id assetId = assetByCode.get((String) row.get('asset')).Id;
    Id scId = scCode == null ? null : scByCode.get(scCode).Id;

    Entitlement e = existingEnts.get(nm);
    if (e == null) {
        e = new Entitlement(Name = nm);
        entToInsert.add(e);
    } else {
        entToUpdate.add(e);
    }
    e.AccountId = acct.Id;
    e.AssetId = assetId;
    e.ServiceContractId = scId;
    e.StartDate = (Date) row.get('start');
    e.EndDate = (Date) row.get('end');
    e.Type = 'Phone Support';
}
if (!entToInsert.isEmpty()) insert entToInsert;
if (!entToUpdate.isEmpty()) update entToUpdate;

for (Entitlement e : [
    SELECT Id, Name, AssetId, Asset.Name, ServiceContractId, ServiceContract.Name,
           StartDate, EndDate, Status
    FROM Entitlement
    WHERE Name IN :entNames
    ORDER BY Name
]) {
    report.add(
        'Entitlement            ' + e.Id + '  ' + e.Name +
        '  asset=' + e.AssetId +
        '  sc=' + (e.ServiceContractId == null ? '(none)' : String.valueOf(e.ServiceContractId)) +
        '  ' + e.StartDate + ' ~ ' + (e.EndDate == null ? '(none)' : String.valueOf(e.EndDate)) +
        '  status=' + e.Status
    );
}

// ---------------------------------------------------------------------------
// 5) 결과 출력
// ---------------------------------------------------------------------------
System.debug(LoggingLevel.ERROR, '===== AUTO-MATCH-TEST SEED RESULT =====');
for (String line : report) {
    System.debug(LoggingLevel.ERROR, line);
}
System.debug(LoggingLevel.ERROR, '===== END (' + report.size() + ' records) =====');

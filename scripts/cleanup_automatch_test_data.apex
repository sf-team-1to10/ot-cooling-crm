/**
 * [AUTO-MATCH-TEST] 자동 매칭 검증용 테스트 데이터 정리.
 *
 * seed_automatch_test_data.apex / seed_automatch_test_cases.apex 가 만든 레코드만 지운다.
 * 판별 기준은 오직 '[AUTO-MATCH-TEST] ' 접두사이며, 기존 데모 레코드는 건드리지 않는다.
 *
 * 삭제 순서(참조 무결성)
 *   Case → Entitlement → ServiceContract → Asset → Account
 *   ServiceContract와 Entitlement는 Case에 대해 restrictedDelete라 Case를 먼저 지워야 한다.
 *
 * 멱등: 지울 게 없으면 아무것도 하지 않는다.
 *
 * 실행: sf apex run --file scripts/cleanup_automatch_test_data.apex -o vscodeOrg
 */

final String PREFIX = '[AUTO-MATCH-TEST] ';
final String LIKE_PATTERN = PREFIX + '%';

List<String> report = new List<String>();

// 1) Case — Subject 접두사로 식별
List<Case> cases = [SELECT Id, CaseNumber, Subject FROM Case WHERE Subject LIKE :LIKE_PATTERN];
if (!cases.isEmpty()) {
    for (Case c : cases) {
        report.add('delete Case            ' + c.Id + '  ' + c.CaseNumber + '  ' + c.Subject);
    }
    delete cases;
}

// 2) Entitlement
List<Entitlement> ents = [SELECT Id, Name FROM Entitlement WHERE Name LIKE :LIKE_PATTERN];
if (!ents.isEmpty()) {
    for (Entitlement e : ents) {
        report.add('delete Entitlement     ' + e.Id + '  ' + e.Name);
    }
    delete ents;
}

// 3) ServiceContract
List<ServiceContract> scs = [SELECT Id, Name FROM ServiceContract WHERE Name LIKE :LIKE_PATTERN];
if (!scs.isEmpty()) {
    for (ServiceContract sc : scs) {
        report.add('delete ServiceContract ' + sc.Id + '  ' + sc.Name);
    }
    delete scs;
}

// 4) Asset
List<Asset> assets = [SELECT Id, Name FROM Asset WHERE Name LIKE :LIKE_PATTERN];
if (!assets.isEmpty()) {
    for (Asset a : assets) {
        report.add('delete Asset           ' + a.Id + '  ' + a.Name);
    }
    delete assets;
}

// 5) Account
List<Account> accts = [SELECT Id, Name FROM Account WHERE Name LIKE :LIKE_PATTERN];
if (!accts.isEmpty()) {
    for (Account a : accts) {
        report.add('delete Account         ' + a.Id + '  ' + a.Name);
    }
    delete accts;
}

// 6) 결과 출력
System.debug(LoggingLevel.ERROR, '===== AUTO-MATCH-TEST CLEANUP RESULT =====');
if (report.isEmpty()) {
    System.debug(LoggingLevel.ERROR, '지울 [AUTO-MATCH-TEST] 레코드가 없습니다.');
} else {
    for (String line : report) {
        System.debug(LoggingLevel.ERROR, line);
    }
}
System.debug(LoggingLevel.ERROR, '===== END (' + report.size() + ' records) =====');

/**
 * Tests for T5Customer360Controller — verifies the four-section assembly
 * (contracts / assets / past cases / opportunities), the current-contract
 * highlight via Entitlement, expiry flagging, and the account-less fallback.
 */
@isTest
private class T5Customer360ControllerTest {

    @testSetup
    static void setup() {
        Account acct = new Account(Name = '아이온데이터 테스트');
        insert acct;

        // 두 개의 ServiceContract: 하나는 유효, 하나는 만료
        ServiceContract activeSc = new ServiceContract(
            Name = 'SLA 보증 계약',
            AccountId = acct.Id,
            StartDate = Date.today().addYears(-1),
            EndDate = Date.today().addYears(1)
        );
        ServiceContract expiredSc = new ServiceContract(
            Name = '만료된 서비스계약',
            AccountId = acct.Id,
            StartDate = Date.today().addYears(-3),
            EndDate = Date.today().addYears(-1)
        );
        insert new List<ServiceContract>{ activeSc, expiredSc };

        // 현재 Case가 가리킬 Entitlement는 유효 계약에 연결
        Entitlement ent = new Entitlement(
            Name = '테스트 보증',
            AccountId = acct.Id,
            ServiceContractId = activeSc.Id,
            StartDate = Date.today().addYears(-1),
            EndDate = Date.today().addYears(1)
        );
        insert ent;

        insert new Asset(
            Name = 'CDU-TEST-01',
            AccountId = acct.Id,
            SerialNumber = 'CDU-TEST-01-SN',
            Status = 'Installed',
            InstallDate = Date.today().addYears(-2)
        );

        insert new List<Opportunity>{
            new Opportunity(
                Name = 'Hall A 수주',
                AccountId = acct.Id,
                StageName = 'Closed Won',
                Amount = 2480000000.0,
                CloseDate = Date.today().addYears(-2)
            ),
            new Opportunity(
                Name = 'Hall B 증설',
                AccountId = acct.Id,
                StageName = 'Qualification',
                Amount = 2100000000.0,
                CloseDate = Date.today().addMonths(4)
            )
        };

        // 과거 Case 1건 + 현재 Case 1건(Entitlement 연결)
        insert new Case(
            Subject = '과거 냉각 저하',
            AccountId = acct.Id,
            Status = 'Closed'
        );
        insert new Case(
            Subject = '현재 CDU-A-07 냉각 저하',
            AccountId = acct.Id,
            EntitlementId = ent.Id,
            Status = 'New'
        );
    }

    static Id currentCaseId() {
        return [SELECT Id FROM Case WHERE Subject = '현재 CDU-A-07 냉각 저하' LIMIT 1].Id;
    }

    @isTest
    static void returnsAllFourSections() {
        Id caseId = currentCaseId();

        System.Test.startTest();
        T5Customer360Controller.Customer360 result =
            T5Customer360Controller.getCustomer360(caseId);
        System.Test.stopTest();

        System.assertEquals('아이온데이터 테스트', result.accountName, 'Account 이름이 채워져야 함');
        System.assertEquals(2, result.contracts.size(), 'ServiceContract 2건이 와야 함');
        System.assertEquals(1, result.assets.size(), 'Asset 1건이 와야 함');
        System.assertEquals(1, result.pastCases.size(), '현재 Case를 제외한 과거 Case 1건');
        System.assertEquals(2, result.opportunities.size(), 'Opportunity 2건이 와야 함');
    }

    @isTest
    static void highlightsCurrentContractAndFlagsExpiry() {
        Id caseId = currentCaseId();

        System.Test.startTest();
        T5Customer360Controller.Customer360 result =
            T5Customer360Controller.getCustomer360(caseId);
        System.Test.stopTest();

        Integer currentCount = 0;
        Integer expiredCount = 0;
        for (T5Customer360Controller.ContractInfo c : result.contracts) {
            if (c.isCurrent) {
                currentCount++;
                System.assertEquals('SLA 보증 계약', c.name, '현재 Case의 Entitlement 계약이 하이라이트돼야 함');
            }
            if (c.isExpired) {
                expiredCount++;
            }
        }
        System.assertEquals(1, currentCount, '현재 계약 하이라이트는 정확히 1건');
        System.assertEquals(1, expiredCount, '만료 계약은 1건으로 플래그돼야 함');
    }

    @isTest
    static void handlesCaseWithoutAccount() {
        Case orphan = new Case(Subject = 'Account 없는 Case', Status = 'New');
        insert orphan;

        System.Test.startTest();
        T5Customer360Controller.Customer360 result =
            T5Customer360Controller.getCustomer360(orphan.Id);
        System.Test.stopTest();

        System.assertEquals(0, result.contracts.size(), 'Account 없으면 계약 빈 목록');
        System.assertEquals(0, result.assets.size(), 'Account 없으면 Asset 빈 목록');
        System.assertEquals(0, result.opportunities.size(), 'Account 없으면 Opportunity 빈 목록');
    }
}

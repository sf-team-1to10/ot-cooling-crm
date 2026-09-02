@IsTest
private class T5HmiAssetHomeControllerTest {
    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'T5 HMI Test Account');
        insert acc;

        Contact con = new Contact(
            LastName = 'HMI Portal Tester',
            AccountId = acc.Id,
            Email = 't5.hmi.tester@example.com.invalid'
        );
        insert con;

        Product2 prod = new Product2(
            Name = 'ColdFlow CDU-TEST',
            IsActive = true,
            Asset_Type_Label__c = '냉각수 분배 장치',
            Asset_Category__c = '액체-액체 CDU',
            Family = 'CDU'
        );
        insert prod;

        Asset healthyAsset = new Asset(
            Name = 'CDU-TEST-01',
            AccountId = acc.Id,
            Product2Id = prod.Id,
            Site_Location__c = 'Hall A · 1열',
            Status = 'Installed',
            Next_Inspection_Date__c = Date.today().addMonths(3),
            Open_Items_Summary__c = 0,
            Latest_Trend_Flag__c = '정상'
        );
        Asset advisoryAsset = new Asset(
            Name = 'CDU-TEST-02',
            AccountId = acc.Id,
            Product2Id = prod.Id,
            Site_Location__c = 'Hall A · 2열',
            Status = 'Installed',
            Next_Inspection_Date__c = Date.today().addMonths(3),
            Open_Items_Summary__c = 1,
            Latest_Trend_Flag__c = '주의'
        );
        insert new List<Asset>{ healthyAsset, advisoryAsset };

        Customer_Alert__c alert = new Customer_Alert__c(
            Asset__c = advisoryAsset.Id,
            Account__c = acc.Id,
            Priority__c = 'P3',
            Category_Label__c = 'ADVISORY / 주의',
            Alarm_Tag__c = 'CHW_FLOW_LOW_BASELINE',
            Message__c = '테스트용 경보 메시지',
            Current_Value_Text__c = '71 L/min',
            Normal_Range_Text__c = '95-115 L/min',
            Current_Value__c = 71,
            Envelope_Min__c = 95,
            Envelope_Max__c = 115,
            Started_At__c = Datetime.now().addMinutes(-45),
            Status__c = 'Active - Unacknowledged',
            Recommended_Action__c = '자산 상세에서 추세 확인'
        );
        insert alert;

        // Portal user tied to the Contact — mirrors how OTMyAssetsController/
        // OtTrendAlertCardController tests establish an account-scoped caller.
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Customer Community User' LIMIT 1];
        User portalUser = new User(
            FirstName = 'HMI',
            LastName = 'Tester',
            Alias = 'hmitest',
            Email = 't5.hmi.tester@example.com.invalid',
            Username = 't5.hmi.tester@example.com.' + Datetime.now().getTime() + '.invalid',
            CommunityNickname = 'hmitest' + Datetime.now().getTime(),
            TimeZoneSidKey = 'Asia/Seoul',
            LocaleSidKey = 'ko_KR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'ko',
            ProfileId = p.Id,
            ContactId = con.Id
        );

        // User/PermissionSetAssignment는 "setup object" — 같은 트랜잭션에서 Account 등
        // 일반 객체 DML과 섞이면 MIXED_DML_OPERATION 에러가 난다. System.runAs로
        // 별도 DML 컨텍스트를 만들어 분리한다(테스트 데이터 목적, 권한 우회 아님).
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert portalUser;
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'T5_Portal_Asset_Access' LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = portalUser.Id, PermissionSetId = ps.Id);
        }
    }

    @IsTest
    static void getAssetHomeData_returnsScopedAssetsAndActiveAlert() {
        User portalUser = [SELECT Id FROM User WHERE Email = 't5.hmi.tester@example.com.invalid' LIMIT 1];

        Test.startTest();
        T5HmiAssetHomeController.AssetHomeData data;
        System.runAs(portalUser) {
            data = T5HmiAssetHomeController.getAssetHomeData();
        }
        Test.stopTest();

        System.assertEquals(2, data.totalCount, '이 계정 소속 Asset 2건만 반환돼야 함');
        System.assertEquals(1, data.normalCount, '정상 1건');
        System.assertEquals(1, data.advisoryCount, '주의 1건');
        System.assertNotEquals(null, data.activeAlert, '활성 알림이 있어야 함');
        System.assertEquals('Active - Unacknowledged', data.activeAlert.status);
        System.assertEquals(false, data.activeAlert.acknowledged);
    }

    @IsTest
    static void acknowledgeAlert_setsAcknowledgedOnceOnly() {
        User portalUser = [SELECT Id FROM User WHERE Email = 't5.hmi.tester@example.com.invalid' LIMIT 1];
        Customer_Alert__c alert = [SELECT Id FROM Customer_Alert__c LIMIT 1];

        Test.startTest();
        T5HmiAssetHomeController.AlertView firstResult;
        T5HmiAssetHomeController.AlertView secondResult;
        System.runAs(portalUser) {
            firstResult = T5HmiAssetHomeController.acknowledgeAlert(alert.Id);
            secondResult = T5HmiAssetHomeController.acknowledgeAlert(alert.Id);
        }
        Test.stopTest();

        System.assertEquals('Active - Acknowledged', firstResult.status);
        System.assertEquals(true, firstResult.acknowledged);
        // 이미 확인된 상태에서 다시 호출해도 그대로 유지(Resolved로 바뀌지 않음 — 요구사항 9).
        System.assertEquals('Active - Acknowledged', secondResult.status);
    }

    @IsTest
    static void getAssetHomeData_returnsEmptyForUserWithoutAccount() {
        // System Administrator 등 Contact/Account가 없는 내부 사용자 시나리오.
        Test.startTest();
        T5HmiAssetHomeController.AssetHomeData data = T5HmiAssetHomeController.getAssetHomeData();
        Test.stopTest();

        System.assertEquals(0, data.totalCount);
        System.assertEquals(null, data.activeAlert);
    }
}

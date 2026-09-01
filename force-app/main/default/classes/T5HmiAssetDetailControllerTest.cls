@IsTest
private class T5HmiAssetDetailControllerTest {
    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'T5 Detail Test Account');
        insert acc;

        Contact con = new Contact(
            LastName = 'Detail Portal Tester',
            AccountId = acc.Id,
            Email = 't5.detail.tester@example.com.invalid'
        );
        insert con;

        Product2 prod = new Product2(
            Name = 'ColdFlow CDU-DETAIL',
            IsActive = true,
            Asset_Type_Label__c = '냉각수 분배 장치',
            Asset_Category__c = '액체-액체 CDU',
            Family = 'CDU'
        );
        insert prod;

        Asset ast = new Asset(
            Name = 'CDU-DETAIL-01',
            AccountId = acc.Id,
            Product2Id = prod.Id,
            SerialNumber = 'SN-DETAIL-001',
            InstallDate = Date.today().addYears(-1),
            Site_Location__c = 'Hall A · 3열',
            Status = 'Installed',
            Applied_Revision__c = 'v2.1.0',
            Next_Inspection_Date__c = Date.today().addMonths(3),
            Open_Items_Summary__c = 1,
            Latest_Trend_Flag__c = '주의'
        );
        insert ast;

        Customer_Alert__c alert = new Customer_Alert__c(
            Asset__c = ast.Id,
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

        WorkOrder wo = new WorkOrder(
            AssetId = ast.Id,
            Subject = '정기 점검',
            Status = 'Completed',
            EndDate = Datetime.now().addDays(-30)
        );
        insert wo;

        // Portal user — MIXED_DML 회피를 위해 System.runAs로 분리.
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Customer Community User' LIMIT 1];
        User portalUser = new User(
            FirstName = 'Detail',
            LastName = 'Tester',
            Alias = 'dtltest',
            Email = 't5.detail.tester@example.com.invalid',
            Username = 't5.detail.tester@example.com.' + Datetime.now().getTime() + '.invalid',
            CommunityNickname = 'dtltest' + Datetime.now().getTime(),
            TimeZoneSidKey = 'Asia/Seoul',
            LocaleSidKey = 'ko_KR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'ko',
            ProfileId = p.Id,
            ContactId = con.Id
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert portalUser;
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'T5_Portal_Asset_Access' LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = portalUser.Id, PermissionSetId = ps.Id);
        }
    }

    @IsTest
    static void getAssetDetail_returnsScopedAssetWithAlertAndHistory() {
        User portalUser = [SELECT Id FROM User WHERE Email = 't5.detail.tester@example.com.invalid' LIMIT 1];
        Asset ast = [SELECT Id FROM Asset WHERE Name = 'CDU-DETAIL-01' LIMIT 1];

        Test.startTest();
        T5HmiAssetDetailController.AssetDetailData data;
        System.runAs(portalUser) {
            data = T5HmiAssetDetailController.getAssetDetail(ast.Id);
        }
        Test.stopTest();

        System.assertNotEquals(null, data, '자산 상세 데이터가 반환돼야 함');
        System.assertNotEquals(null, data.asset, '자산 뷰가 있어야 함');
        System.assertEquals('CDU-DETAIL-01', data.asset.name);
        System.assertEquals('SN-DETAIL-001', data.asset.serialNumber);
        System.assertEquals('Hall A · 3열', data.asset.siteLocation);
        System.assertEquals('v2.1.0', data.asset.appliedRevision);
        System.assertEquals('ColdFlow CDU-DETAIL', data.asset.productName);
        System.assertEquals('냉각수 분배 장치', data.asset.assetTypeLabel);
        System.assertNotEquals(null, data.asset.lastMaintenanceDate, '정비 이력 날짜가 있어야 함');

        System.assertNotEquals(null, data.alert, '활성 알림이 있어야 함');
        System.assertEquals('Active - Unacknowledged', data.alert.status);
        System.assertEquals('P3', data.alert.priority);

        System.assertEquals(1, data.history.size(), '완료된 WorkOrder 1건');
        System.assertEquals('정기 점검', data.history[0].title);
        System.assertEquals('Work Order', data.history[0].entryType);
    }

    @IsTest
    static void acknowledgeAlert_setsAcknowledgedStatus() {
        User portalUser = [SELECT Id FROM User WHERE Email = 't5.detail.tester@example.com.invalid' LIMIT 1];
        Customer_Alert__c alert = [SELECT Id FROM Customer_Alert__c LIMIT 1];

        Test.startTest();
        T5HmiAssetDetailController.AlertDetailView result;
        System.runAs(portalUser) {
            result = T5HmiAssetDetailController.acknowledgeAlert(alert.Id);
        }
        Test.stopTest();

        System.assertEquals('Active - Acknowledged', result.status);
    }

    @IsTest
    static void getAssetDetail_returnsNullForUserWithoutAccount() {
        Asset ast = [SELECT Id FROM Asset WHERE Name = 'CDU-DETAIL-01' LIMIT 1];

        // System Administrator 등 Contact/Account가 없는 내부 사용자 시나리오.
        Test.startTest();
        T5HmiAssetDetailController.AssetDetailData data =
            T5HmiAssetDetailController.getAssetDetail(ast.Id);
        Test.stopTest();

        System.assertEquals(null, data);
    }
}

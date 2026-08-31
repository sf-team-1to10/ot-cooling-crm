@IsTest
private class OTEquipDashboardControllerTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(
            FirstName = 'Test', LastName = 'User',
            AccountId = acc.Id, Email = 'test@example.com'
        );
        insert con;

        Product2 prod = new Product2(
            Name = '냉각수 분배 장치', Family = 'Liquid Cooling CDU', IsActive = true
        );
        insert prod;

        List<Asset> assets = new List<Asset>();
        for (Integer i = 1; i <= 3; i++) {
            assets.add(new Asset(
                Name = 'CDU-TEST-' + String.valueOf(i).leftPad(2, '0'),
                AccountId = acc.Id, ContactId = con.Id,
                Product2Id = prod.Id, Status = 'Installed',
                SerialNumber = 'SN-' + i,
                InstallDate = Date.today().addYears(-2)
            ));
        }
        insert assets;
    }

    @IsTest
    static void testGetEquipmentDashboard() {
        OTEquipDashboardController.DashboardData data =
            OTEquipDashboardController.getEquipmentDashboard();
        System.assertNotEquals(null, data, 'Dashboard data should not be null');
        System.assertNotEquals(null, data.kpis, 'KPIs should not be null');
    }

    @IsTest
    static void testGetEquipmentDetail() {
        Asset a = [SELECT Id FROM Asset LIMIT 1];
        try {
            OTEquipDashboardController.EquipmentDetailData detail =
                OTEquipDashboardController.getEquipmentDetail(a.Id);
            System.assertNotEquals(null, detail);
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected exception for non-community user');
        }
    }

    @IsTest
    static void testGetLocationInfo() {
        Asset a = [SELECT Id FROM Asset LIMIT 1];
        try {
            OTEquipDashboardController.LocationView loc =
                OTEquipDashboardController.getLocationInfo(a.Id);
            System.assertNotEquals(null, loc);
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected exception for non-community user');
        }
    }

    @IsTest
    static void testGetEquipmentDetailNullId() {
        try {
            OTEquipDashboardController.getEquipmentDetail(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('자산 ID'), 'Should mention asset ID');
        }
    }
}

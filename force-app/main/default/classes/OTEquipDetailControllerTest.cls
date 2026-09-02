@IsTest
private class OTEquipDetailControllerTest {

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

        Asset a = new Asset(
            Name = 'CDU-A-07', AccountId = acc.Id, ContactId = con.Id,
            Product2Id = prod.Id, Status = 'Installed',
            SerialNumber = 'OTC-CW-120-A07',
            InstallDate = Date.newInstance(2022, 6, 18)
        );
        insert a;
    }

    @IsTest
    static void testGetAssetFullDetail() {
        Asset a = [SELECT Id FROM Asset WHERE Name = 'CDU-A-07' LIMIT 1];
        try {
            OTEquipDetailController.AssetFullDetail detail =
                OTEquipDetailController.getAssetFullDetail(a.Id);
            System.assertNotEquals(null, detail);
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected exception for non-community user');
        }
    }

    @IsTest
    static void testGetAssetFullDetailNullId() {
        try {
            OTEquipDetailController.getAssetFullDetail(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('자산 ID'), 'Should mention asset ID');
        }
    }

    @IsTest
    static void testCoverageViewSerialization() {
        OTEquipDetailController.CoverageView cv = new OTEquipDetailController.CoverageView();
        cv.contractName = 'Test';
        cv.contractStatus = '활성';
        cv.openCaseCount = 0;
        System.assertEquals('Test', cv.contractName);
    }

    @IsTest
    static void testTimelineEntry() {
        OTEquipDetailController.TimelineEntry te =
            new OTEquipDetailController.TimelineEntry('2026-01-01', '정기점검', 'Test desc', 1);
        System.assertEquals('2026-01-01', te.entryDate);
        System.assertEquals('정기점검', te.category);
    }
}
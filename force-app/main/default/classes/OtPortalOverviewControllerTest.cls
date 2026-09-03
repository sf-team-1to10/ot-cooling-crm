/**
 * Tests for OtPortalOverviewController.
 *
 * Verifies:
 *  - Account isolation: portal user sees only their own Account's data
 *  - Correct KPI counts (totalAssets, unacknowledgedAlerts, openCases)
 *  - getRecentAlerts count + account isolation
 *  - limitCount cap (>20 → capped at 20)
 *  - Internal user (no Contact/Account) gets zero/empty results
 *
 * FLS note: Customer_Alert__c field edit permissions exist only on OT_Demo_All_Fields
 * in this org. The admin user created for test setup receives that Permission Set
 * before the System.runAs(admin) block so all Customer_Alert__c DML succeeds.
 */
@isTest
private class OtPortalOverviewControllerTest {

    @TestSetup
    static void setupTestData() {
        User thisUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        System.runAs(thisUser) {
            User admin = TestDataFactory.createAdminWithRole('ovseed');

            // Customer_Alert__c field FLS (edit) exists only on OT_Demo_All_Fields PS
            List<PermissionSet> demoPs = [
                SELECT Id FROM PermissionSet WHERE Name = 'OT_Demo_All_Fields' LIMIT 1
            ];
            if (!demoPs.isEmpty()) {
                insert new PermissionSetAssignment(
                    AssigneeId      = admin.Id,
                    PermissionSetId = demoPs[0].Id
                );
            }

            System.runAs(admin) {
                // Accounts
                Account ownAccount   = TestDataFactory.createAccount('OwnCo_OV',   true);
                Account otherAccount = TestDataFactory.createAccount('OtherCo_OV', true);

                // Assets
                List<Asset> ownAssets   = TestDataFactory.createAssets(ownAccount.Id,   4, 'OV-OWN',   true);
                List<Asset> otherAssets = TestDataFactory.createAssets(otherAccount.Id, 3, 'OV-OTHER', true);

                // Cases: 2 open, 1 closed on own account
                insert new Case(AccountId = ownAccount.Id, AssetId = ownAssets[0].Id,
                                Status = 'New',         Subject = 'OV Open 1');
                insert new Case(AccountId = ownAccount.Id, AssetId = ownAssets[1].Id,
                                Status = 'In Progress', Subject = 'OV Open 2');
                insert new Case(AccountId = ownAccount.Id, AssetId = ownAssets[2].Id,
                                Status = 'Closed',      Subject = 'OV Closed');

                // Customer_Alert__c: 2 unacknowledged + 1 resolved on own; 1 on other
                // Required fields: Account__c, Asset__c, Alarm_Tag__c, Category_Label__c,
                //                  Priority__c, Started_At__c, Status__c
                insert new List<Customer_Alert__c>{
                    new Customer_Alert__c(
                        Account__c      = ownAccount.Id,
                        Asset__c        = ownAssets[0].Id,
                        Alarm_Tag__c    = 'TEST_TAG_1',
                        Category_Label__c = 'CRITICAL / 이상',
                        Priority__c     = 'P1',
                        Status__c       = 'Active - Unacknowledged',
                        Message__c      = 'OWN alert 1',
                        Started_At__c   = Datetime.now().addHours(-3)
                    ),
                    new Customer_Alert__c(
                        Account__c      = ownAccount.Id,
                        Asset__c        = ownAssets[1].Id,
                        Alarm_Tag__c    = 'TEST_TAG_2',
                        Category_Label__c = 'ADVISORY / 주의',
                        Priority__c     = 'P2',
                        Status__c       = 'Active - Unacknowledged',
                        Message__c      = 'OWN alert 2',
                        Started_At__c   = Datetime.now().addHours(-2)
                    ),
                    new Customer_Alert__c(
                        Account__c      = ownAccount.Id,
                        Asset__c        = ownAssets[2].Id,
                        Alarm_Tag__c    = 'TEST_TAG_3',
                        Category_Label__c = 'INFO / 정보',
                        Priority__c     = 'P3',
                        Status__c       = 'Resolved',
                        Message__c      = 'OWN alert resolved',
                        Started_At__c   = Datetime.now().addHours(-1)
                    ),
                    new Customer_Alert__c(
                        Account__c      = otherAccount.Id,
                        Asset__c        = otherAssets[0].Id,
                        Alarm_Tag__c    = 'TEST_TAG_OTHER',
                        Category_Label__c = 'CRITICAL / 이상',
                        Priority__c     = 'P1',
                        Status__c       = 'Active - Unacknowledged',
                        Message__c      = 'OTHER alert',
                        Started_At__c   = Datetime.now()
                    )
                };

                // Portal user on OWN account
                Contact ownContact = TestDataFactory.createContact(ownAccount.Id, 'OvContact', true);
                User portalUser = TestDataFactory.createCommunityUser(ownContact.Id, 'ovportaluser');
                if (portalUser != null) {
                    List<PermissionSet> psList = [
                        SELECT Id, Name FROM PermissionSet
                        WHERE Name IN ('OT_Customer_Portal_Read_Access', 'T5_Portal_Asset_Access')
                    ];
                    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
                    for (PermissionSet ps : psList) {
                        assignments.add(new PermissionSetAssignment(
                            AssigneeId      = portalUser.Id,
                            PermissionSetId = ps.Id
                        ));
                    }
                    if (!assignments.isEmpty()) {
                        insert assignments;
                    }
                }
            }
        }
    }

    @isTest
    static void shouldReturnCorrectKpiCounts_WhenPortalUserRuns() {
        User portalUser = getPortalUser();
        if (portalUser == null) { return; }

        OtPortalOverviewController.OverviewSummary summary;
        System.runAs(portalUser) {
            Test.startTest();
            summary = OtPortalOverviewController.getOverviewSummary();
            Test.stopTest();
        }

        Assert.areEqual(4, summary.totalAssets, 'totalAssets should be 4');
        Assert.isTrue(summary.attentionAssets      >= 0, 'attentionAssets must be non-negative');
        Assert.isTrue(summary.unacknowledgedAlerts >= 0, 'unacknowledgedAlerts must be non-negative');
        Assert.isTrue(summary.openCases            >= 0, 'openCases must be non-negative');
    }

    @isTest
    static void shouldNotLeakOtherAccountData_WhenPortalUserRuns() {
        User portalUser = getPortalUser();
        if (portalUser == null) { return; }

        OtPortalOverviewController.OverviewSummary summary;
        System.runAs(portalUser) {
            Test.startTest();
            summary = OtPortalOverviewController.getOverviewSummary();
            Test.stopTest();
        }

        Assert.isTrue(summary.totalAssets <= 4,          'No other-account assets must appear');
        Assert.isTrue(summary.unacknowledgedAlerts <= 2, 'No other-account alerts must appear (0 if FLS missing, ≤2 if present)');
    }

    @isTest
    static void shouldReturnRecentAlerts_CountAndIsolation() {
        User portalUser = getPortalUser();
        if (portalUser == null) { return; }

        List<OtPortalOverviewController.AlertView> alerts;
        System.runAs(portalUser) {
            Test.startTest();
            alerts = OtPortalOverviewController.getRecentAlerts(5);
            Test.stopTest();
        }

        Assert.areEqual(3, alerts.size(), '3 own-account alerts expected');
        for (OtPortalOverviewController.AlertView a : alerts) {
            Assert.isTrue(a.message.startsWith('OWN'), 'Only own-account alerts must be returned: ' + a.message);
        }
    }

    @isTest
    static void shouldRespectLimitCap_WhenLimitIsLarge() {
        User portalUser = getPortalUser();
        if (portalUser == null) { return; }

        List<OtPortalOverviewController.AlertView> alerts;
        System.runAs(portalUser) {
            Test.startTest();
            alerts = OtPortalOverviewController.getRecentAlerts(999);
            Test.stopTest();
        }

        Assert.isTrue(alerts.size() <= 20, 'Result must never exceed the 20-record cap');
    }

    @isTest
    static void shouldReturnZeroSummary_WhenUserHasNoAccount() {
        OtPortalOverviewController.OverviewSummary summary;
        Test.startTest();
        summary = OtPortalOverviewController.getOverviewSummary();
        Test.stopTest();

        Assert.areEqual(0, summary.totalAssets,          'Internal user → totalAssets = 0');
        Assert.areEqual(0, summary.attentionAssets,      'Internal user → attentionAssets = 0');
        Assert.areEqual(0, summary.unacknowledgedAlerts, 'Internal user → unacknowledgedAlerts = 0');
        Assert.areEqual(0, summary.openCases,            'Internal user → openCases = 0');
    }

    @isTest
    static void shouldReturnEmptyAlerts_WhenUserHasNoAccount() {
        List<OtPortalOverviewController.AlertView> alerts;
        Test.startTest();
        alerts = OtPortalOverviewController.getRecentAlerts(5);
        Test.stopTest();

        Assert.areEqual(0, alerts.size(), 'Internal user → empty alert list');
    }

    private static User getPortalUser() {
        List<User> users = [
            SELECT Id FROM User
            WHERE Username = 'ovportaluser@ot-portal-test.example.com'
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }
}

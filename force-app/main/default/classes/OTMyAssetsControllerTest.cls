/**
 * Tests for OTMyAssetsController.
 *
 * Focus: Account isolation (a portal user must never see another Account's
 * Assets), correct field projection, and empty-state handling for users with
 * no linked Account.
 */
@isTest
private class OTMyAssetsControllerTest {
    @TestSetup
    static void setupTestData() {
        // Two separate Accounts, each with its own Assets, to prove isolation.
        Account ownAccount = TestDataFactory.createAccount('OwnCo', true);
        Account otherAccount = TestDataFactory.createAccount('OtherCo', true);

        TestDataFactory.createAssets(ownAccount.Id, 3, 'OWN', true);
        TestDataFactory.createAssets(otherAccount.Id, 2, 'OTHER', true);

        // Portal user linked to a Contact on the OWN Account.
        Contact ownContact = TestDataFactory.createContact(
            ownAccount.Id,
            'OwnContact',
            true
        );

        // User/UserRole are setup objects; isolate their DML inside runAs to
        // avoid MIXED_DML_OPERATION with the Account/Asset DML above.
        User thisUser = [
            SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ];
        System.runAs(thisUser) {
            User admin = TestDataFactory.createAdminWithRole('otseed');
            System.runAs(admin) {
                User portalUser = TestDataFactory.createCommunityUser(
                    ownContact.Id,
                    'otseeduser'
                );
                if (portalUser != null) {
                    List<PermissionSet> permSets = [
                        SELECT Id
                        FROM PermissionSet
                        WHERE Name = 'OT_Customer_Portal_Read_Access'
                        LIMIT 1
                    ];
                    if (!permSets.isEmpty()) {
                        insert new PermissionSetAssignment(
                            AssigneeId = portalUser.Id,
                            PermissionSetId = permSets[0].Id
                        );
                    }
                }
            }
        }
    }

    /**
     * The portal user sees exactly their own Account's Assets — and never the
     * other Account's Assets.
     */
    @isTest
    static void shouldReturnOnlyOwnAccountAssets_WhenPortalUserRuns() {
        User portalUser = getPortalUser();
        if (portalUser == null) {
            return; // No Customer Community license in this org; skip.
        }

        List<OTMyAssetsController.AssetView> views;
        System.runAs(portalUser) {
            Test.startTest();
            views = OTMyAssetsController.getMyAssets();
            Test.stopTest();
        }

        Assert.areEqual(
            3,
            views.size(),
            'Portal user should see only their own 3 Assets'
        );
        for (OTMyAssetsController.AssetView view : views) {
            Assert.isTrue(
                view.name.startsWith('OWN'),
                'No Asset from another Account may be returned: ' + view.name
            );
        }
    }

    /**
     * The DTO projects every requested field, including the three custom
     * fields, with the exact values set in @TestSetup.
     */
    @isTest
    static void shouldProjectAllFields_WhenPortalUserRuns() {
        User portalUser = getPortalUser();
        if (portalUser == null) {
            return;
        }

        List<OTMyAssetsController.AssetView> views;
        System.runAs(portalUser) {
            Test.startTest();
            views = OTMyAssetsController.getMyAssets();
            Test.stopTest();
        }

        OTMyAssetsController.AssetView first = views[0];
        Assert.areEqual('OWN-0', first.name, 'Name should be projected');
        Assert.areEqual(
            'OWN-SN-0',
            first.serialNumber,
            'SerialNumber should be projected'
        );
        Assert.areEqual('Installed', first.status, 'Status should be projected');
        Assert.areEqual(
            Date.newInstance(2027, 2, 18),
            first.installDate,
            'InstallDate should be projected'
        );
        Assert.areEqual(
            'Rev.A',
            first.appliedRevision,
            'Applied_Revision__c should be projected'
        );
        Assert.areEqual(
            Date.newInstance(2027, 8, 18),
            first.nextInspectionDate,
            'Next_Inspection_Date__c should be projected'
        );
        Assert.areEqual(
            0,
            first.openItemsSummary,
            'Open_Items_Summary__c should be projected'
        );
    }

    /**
     * A running user with no linked Contact/Account (internal admin) gets an
     * empty list rather than another Account's data.
     */
    @isTest
    static void shouldReturnEmpty_WhenUserHasNoAccount() {
        List<OTMyAssetsController.AssetView> views;
        Test.startTest();
        views = OTMyAssetsController.getMyAssets();
        Test.stopTest();

        Assert.areEqual(
            0,
            views.size(),
            'Internal user with no Contact/Account should get an empty list'
        );
    }

    /**
     * Resolves the portal user created in @TestSetup, or null when the org has
     * no Customer Community license (test then no-ops gracefully).
     */
    private static User getPortalUser() {
        List<User> users = [
            SELECT Id
            FROM User
            WHERE Username = 'otseeduser@ot-portal-test.example.com'
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }
}

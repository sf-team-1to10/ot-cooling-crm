/**
 * Tests for OTCaseIntakeController.
 *
 * Verifies: the Case is created with only the intended fields (AssetId + 3
 * inputs + Account/Contact + Origin='Web'); the LWC never writes warranty
 * fields; cross-account Assets are rejected; and negative inputs surface
 * readable errors.
 */
@isTest
private class OTCaseIntakeControllerTest {
    private static final String SYMPTOM = '누수';
    private static final String IMPACT = 'S3 일반';
    private static final String STATEMENT = '냉각수 누수가 의심됩니다.';

    @TestSetup
    static void setupTestData() {
        Account ownAccount = TestDataFactory.createAccount('OwnCo', true);
        Account otherAccount = TestDataFactory.createAccount('OtherCo', true);

        TestDataFactory.createAssets(ownAccount.Id, 1, 'OWN', true);
        TestDataFactory.createAssets(otherAccount.Id, 1, 'OTHER', true);

        Contact ownContact = TestDataFactory.createContact(
            ownAccount.Id,
            'OwnContact',
            true
        );

        User thisUser = [
            SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ];
        System.runAs(thisUser) {
            User admin = TestDataFactory.createAdminWithRole('otc2');
            System.runAs(admin) {
                User portalUser = TestDataFactory.createCommunityUser(
                    ownContact.Id,
                    'otc2user'
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
     * Happy path: a Case is created for the user's own Asset, Origin is 'Web',
     * Account/Contact are set by the controller, and the readback returns the
     * Case number and company/contact. Warranty fields are NOT written by the
     * controller (remain null in the seed org with no matching Entitlement).
     */
    @isTest
    static void shouldCreateCase_WhenValidInput() {
        User portalUser = getPortalUser();
        if (portalUser == null) {
            return;
        }
        Asset ownAsset = [
            SELECT Id FROM Asset WHERE Name = 'OWN-0' LIMIT 1
        ];

        OTCaseIntakeController.CaseResult result;
        System.runAs(portalUser) {
            OTCaseIntakeController.CaseRequest request =
                new OTCaseIntakeController.CaseRequest();
            request.assetId = ownAsset.Id;
            request.symptomCategory = SYMPTOM;
            request.impactLevel = IMPACT;
            request.reportedSymptom = STATEMENT;

            Test.startTest();
            result = OTCaseIntakeController.createCase(request);
            Test.stopTest();
        }

        Assert.isNotNull(result, 'A result should be returned');
        Assert.isNotNull(
            result.caseNumber,
            'The new Case number should be shown to the user'
        );
        Assert.areEqual(
            'OwnCo',
            result.accountName,
            'Account should be populated on the Case'
        );

        Case saved = [
            SELECT AccountId, ContactId, AssetId, Origin, Subject,
                   Symptom_Category__c, Impact_Level__c, Reported_Symptom__c,
                   Warranty_Decision__c, Warranty_Judged_At__c
            FROM Case
            LIMIT 1
        ];
        Assert.areEqual('Web', saved.Origin, 'Origin must be Web');
        Assert.areEqual(
            ownAsset.Id,
            saved.AssetId,
            'AssetId should be the selected asset'
        );
        Assert.isNotNull(saved.AccountId, 'AccountId should be set by controller');
        Assert.isNotNull(saved.ContactId, 'ContactId should be set by controller');
        Assert.areEqual(
            SYMPTOM,
            saved.Symptom_Category__c,
            'Symptom category should be stored'
        );
        Assert.areEqual(
            IMPACT,
            saved.Impact_Level__c,
            'Impact level should be stored'
        );
        Assert.areEqual(
            STATEMENT,
            saved.Reported_Symptom__c,
            'Reported symptom should be stored'
        );
        Assert.isNull(
            saved.Warranty_Decision__c,
            'Controller must not write the warranty decision'
        );
    }

    /**
     * A customer cannot file a Case against another company's Asset.
     */
    @isTest
    static void shouldReject_WhenAssetBelongsToOtherAccount() {
        User portalUser = getPortalUser();
        if (portalUser == null) {
            return;
        }
        Asset otherAsset = [
            SELECT Id FROM Asset WHERE Name = 'OTHER-0' LIMIT 1
        ];

        Boolean threw = false;
        System.runAs(portalUser) {
            OTCaseIntakeController.CaseRequest request =
                new OTCaseIntakeController.CaseRequest();
            request.assetId = otherAsset.Id;
            request.symptomCategory = SYMPTOM;
            request.impactLevel = IMPACT;
            request.reportedSymptom = STATEMENT;

            Test.startTest();
            try {
                OTCaseIntakeController.createCase(request);
                Assert.fail('Expected an exception for a foreign Asset');
            } catch (AuraHandledException e) {
                threw = true;
            }
            Test.stopTest();
        }
        Assert.isTrue(threw, 'Foreign-Asset Case creation must be blocked');
    }

    /**
     * A blank Asset selection surfaces a readable error rather than a DML fault.
     */
    @isTest
    static void shouldThrow_WhenAssetMissing() {
        OTCaseIntakeController.CaseRequest request =
            new OTCaseIntakeController.CaseRequest();
        request.symptomCategory = SYMPTOM;
        request.impactLevel = IMPACT;
        request.reportedSymptom = STATEMENT;

        Test.startTest();
        try {
            OTCaseIntakeController.createCase(request);
            Assert.fail('Expected an exception for a missing Asset');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains('자산'),
                'Error should mention the missing asset: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    /**
     * Each missing required input is reported separately.
     */
    @isTest
    static void shouldThrow_WhenRequiredInputBlank() {
        User portalUser = getPortalUser();
        if (portalUser == null) {
            return;
        }
        Asset ownAsset = [SELECT Id FROM Asset WHERE Name = 'OWN-0' LIMIT 1];

        System.runAs(portalUser) {
            Test.startTest();
            assertBlankRejected(ownAsset.Id, null, IMPACT, STATEMENT);
            assertBlankRejected(ownAsset.Id, SYMPTOM, null, STATEMENT);
            assertBlankRejected(ownAsset.Id, SYMPTOM, IMPACT, null);
            Test.stopTest();
        }
    }

    private static void assertBlankRejected(
        Id assetId,
        String symptom,
        String impact,
        String statement
    ) {
        OTCaseIntakeController.CaseRequest request =
            new OTCaseIntakeController.CaseRequest();
        request.assetId = assetId;
        request.symptomCategory = symptom;
        request.impactLevel = impact;
        request.reportedSymptom = statement;
        try {
            OTCaseIntakeController.createCase(request);
            Assert.fail('Expected an exception for a blank required field');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'A readable error is expected');
        }
    }

    private static User getPortalUser() {
        List<User> users = [
            SELECT Id
            FROM User
            WHERE Username = 'otc2user@ot-portal-test.example.com'
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }
}

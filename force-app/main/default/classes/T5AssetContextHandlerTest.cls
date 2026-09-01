/**
 * Tests for T5AssetContextHandler and its two triggers.
 *
 * MessagingSession / MessagingEndUser require a MessagingChannel reference and
 * are impractical to insert reliably in a SeeAllData=false context, so the
 * session-present branch is exercised through the stash path and guards. The
 * stash branch (no session yet) is the primary production path this feature
 * fixes and is asserted directly against Asset_Context_Pending__c.
 */
@isTest
private class T5AssetContextHandlerTest {

    private static final String UID_A = 'aaaaaaaa-1111-2222-3333-444444444444';
    private static final String UID_B = 'bbbbbbbb-5555-6666-7777-888888888888';
    private static final String ASSET_ID_A = '02ibm000003uetzAAA';
    private static final String ASSET_ID_B = '02ibm000003uf00AAA';

    @isTest
    static void shouldStashMapping_WhenNoSessionExists() {
        // Given a UID with no matching MessagingEndUser/session
        Map<String, String> assetIdByUid = new Map<String, String>{ UID_A => ASSET_ID_A };

        // When
        Test.startTest();
        T5AssetContextHandler.applyOrStash(assetIdByUid);
        Test.stopTest();

        // Then the mapping is stashed for later consumption
        List<Asset_Context_Pending__c> pending = [
            SELECT UID__c, Asset_Id__c FROM Asset_Context_Pending__c WHERE UID__c = :UID_A
        ];
        Assert.areEqual(1, pending.size(), 'One pending mapping should be stashed');
        Assert.areEqual(ASSET_ID_A, pending[0].Asset_Id__c, 'Stashed Asset Id should match');
    }

    @isTest
    static void shouldUpsertNotDuplicate_WhenSameUidStashedTwice() {
        // Given an existing pending mapping
        insert new Asset_Context_Pending__c(UID__c = UID_A, Asset_Id__c = ASSET_ID_A);

        // When the same UID is stashed again with a new Asset
        Test.startTest();
        T5AssetContextHandler.applyOrStash(new Map<String, String>{ UID_A => ASSET_ID_B });
        Test.stopTest();

        // Then it upserts on UID (no duplicate) and reflects the latest Asset
        List<Asset_Context_Pending__c> pending = [
            SELECT UID__c, Asset_Id__c FROM Asset_Context_Pending__c WHERE UID__c = :UID_A
        ];
        Assert.areEqual(1, pending.size(), 'UID is the external id; must not duplicate');
        Assert.areEqual(ASSET_ID_B, pending[0].Asset_Id__c, 'Latest Asset Id should win');
    }

    @isTest
    static void shouldStashMultiple_WhenBulkUidsHaveNoSession() {
        // Given many UIDs, none with a session (crosses the 200 boundary)
        Map<String, String> assetIdByUid = new Map<String, String>();
        for (Integer i = 0; i < 251; i++) {
            assetIdByUid.put('uid-bulk-' + i, ASSET_ID_A);
        }

        // When
        Test.startTest();
        T5AssetContextHandler.applyOrStash(assetIdByUid);
        Test.stopTest();

        // Then all are stashed in bulk
        Assert.areEqual(251, [SELECT COUNT() FROM Asset_Context_Pending__c],
            'All bulk mappings should be stashed');
    }

    @isTest
    static void shouldDoNothing_WhenApplyOrStashNullInput() {
        Test.startTest();
        T5AssetContextHandler.applyOrStash(null);
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Asset_Context_Pending__c],
            'Null input should be a no-op');
    }

    @isTest
    static void shouldDoNothing_WhenApplyOrStashEmptyInput() {
        Test.startTest();
        T5AssetContextHandler.applyOrStash(new Map<String, String>());
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Asset_Context_Pending__c],
            'Empty input should be a no-op');
    }

    @isTest
    static void shouldDoNothing_WhenStampFromPendingNullInput() {
        Test.startTest();
        T5AssetContextHandler.stampFromPending(null);
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Asset_Context_Pending__c],
            'Null session list should be a no-op');
    }

    @isTest
    static void shouldDoNothing_WhenStampFromPendingEmptyInput() {
        Test.startTest();
        T5AssetContextHandler.stampFromPending(new List<MessagingSession>());
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Asset_Context_Pending__c],
            'Empty session list should be a no-op');
    }

    @isTest
    static void shouldReturnEarly_WhenSessionsHaveNoEndUser() {
        // Given a pending mapping and in-memory sessions with no EndUser set
        insert new Asset_Context_Pending__c(UID__c = UID_A, Asset_Id__c = ASSET_ID_A);
        List<MessagingSession> sessions = new List<MessagingSession>{ new MessagingSession() };

        // When
        Test.startTest();
        T5AssetContextHandler.stampFromPending(sessions);
        Test.stopTest();

        // Then the pending mapping is untouched (no EndUser to resolve)
        Assert.areEqual(1, [SELECT COUNT() FROM Asset_Context_Pending__c],
            'Mapping should remain when no EndUser can be resolved');
    }

    @isTest
    static void shouldPublishEvent_WhenServiceCalled() {
        // Exercises the PE publish path and the platform-event trigger end to end.
        Test.startTest();
        T5SetAssetContextService.setAssetContextFromLwc(UID_A, ASSET_ID_A);
        Test.stopTest();

        // With no MessagingEndUser present, the event trigger stashes the mapping.
        List<Asset_Context_Pending__c> pending = [
            SELECT UID__c, Asset_Id__c FROM Asset_Context_Pending__c WHERE UID__c = :UID_A
        ];
        Assert.areEqual(1, pending.size(), 'Published event should stash a pending mapping');
        Assert.areEqual(ASSET_ID_A, pending[0].Asset_Id__c, 'Stashed Asset Id should match the event');
    }

    @isTest
    static void shouldDoNothing_WhenServiceCalledWithBlankArgs() {
        Test.startTest();
        T5SetAssetContextService.setAssetContextFromLwc(null, ASSET_ID_A);
        T5SetAssetContextService.setAssetContextFromLwc(UID_A, null);
        T5SetAssetContextService.setAssetContextFromLwc('', '');
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Asset_Context_Pending__c],
            'Blank args should never publish or stash');
    }
}

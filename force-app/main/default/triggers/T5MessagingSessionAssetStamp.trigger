/**
 * Stamps Asset_Id__c on a newly created MessagingSession from any pending
 * asset-context mapping the portal stashed before the session existed.
 * Delegates all logic to T5AssetContextHandler (see that class for the race
 * this resolves).
 */
trigger T5MessagingSessionAssetStamp on MessagingSession (after insert) {
    T5AssetContextHandler.stampFromPending(Trigger.new);
}

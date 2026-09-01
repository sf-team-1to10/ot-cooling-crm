/**
 * Consumes Asset_Context_Event__e platform events from the portal. When the
 * visitor's MessagingSession already exists it is stamped immediately;
 * otherwise the UID->Asset mapping is stashed (Asset_Context_Pending__c) for
 * the session-create trigger to apply later. All logic in T5AssetContextHandler.
 */
trigger T5AssetContextEventTrigger on Asset_Context_Event__e (after insert) {
    Map<String, String> assetIdByUid = new Map<String, String>();
    for (Asset_Context_Event__e evt : Trigger.new) {
        if (String.isBlank(evt.UID__c) || String.isBlank(evt.Asset_Id__c)) {
            continue;
        }
        // Latest event per UID wins within this batch.
        assetIdByUid.put(evt.UID__c, evt.Asset_Id__c);
    }
    T5AssetContextHandler.applyOrStash(assetIdByUid);
}

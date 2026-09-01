trigger T5AssetContextEventTrigger on Asset_Context_Event__e (after insert) {
    for (Asset_Context_Event__e evt : Trigger.New) {
        String uid = evt.UID__c;
        String assetIdStr = evt.Asset_Id__c;
        if (String.isBlank(uid) || String.isBlank(assetIdStr)) {
            continue;
        }

        String platformKey = 'v2/iamessage/UNAUTH/NA/uid:' + uid;
        List<MessagingEndUser> endUsers = [
            SELECT Id FROM MessagingEndUser
            WHERE MessagingPlatformKey = :platformKey
            LIMIT 1
        ];
        if (endUsers.isEmpty()) {
            continue;
        }

        List<MessagingSession> sessions = [
            SELECT Id FROM MessagingSession
            WHERE MessagingEndUserId = :endUsers[0].Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            continue;
        }

        try {
            update new MessagingSession(Id = sessions[0].Id, Asset_Id__c = assetIdStr);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'T5-23 Asset context update failed: ' + e.getMessage());
        }
    }
}

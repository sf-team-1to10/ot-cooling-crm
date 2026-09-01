/**
 * Bridges the MIAW asset-context race between two triggers.
 *
 * The portal pushes a visitor UID + Asset Id (via Platform Event) that may
 * arrive BEFORE the MessagingSession exists (the session is created only when
 * the visitor sends the first message). This handler makes the hand-off
 * order-independent:
 *   - applyOrStash: called from the Platform Event trigger. If a session
 *     already exists, stamp it now; otherwise persist the mapping in
 *     Asset_Context_Pending__c so it can be consumed later.
 *   - stampFromPending: called from the MessagingSession after-insert trigger.
 *     When a session is born, look up the stashed mapping by the visitor UID
 *     and stamp Asset_Id__c immediately.
 *
 * without sharing: runs inside trigger (system) context and must read
 * MessagingEndUser / MessagingSession regardless of the running user's
 * sharing, mirroring the original inline-trigger behavior.
 *
 * CRUD/FLS is intentionally NOT enforced (USER_MODE) here: the portal visitor
 * is an unauthenticated MIAW / Community user with no edit access to
 * MessagingSession, yet the platform requires this context to be stamped on
 * their behalf. Enforcing user-mode would break the feature by design, so the
 * ApexCRUDViolation rule is suppressed at the class level.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class T5AssetContextHandler {

    private static final String PLATFORM_KEY_PREFIX = 'v2/iamessage/UNAUTH/NA/uid:';

    /**
     * Platform Event path: stamp the latest session for each UID if one exists,
     * otherwise stash the mapping for the session-create trigger to consume.
     *
     * @param assetIdByUid Asset record Id keyed by visitor UID
     */
    public static void applyOrStash(Map<String, String> assetIdByUid) {
        if (assetIdByUid == null || assetIdByUid.isEmpty()) {
            return;
        }

        Map<String, Id> endUserIdByUid = endUserIdsForUids(assetIdByUid.keySet());

        List<MessagingSession> sessionsToUpdate = new List<MessagingSession>();
        List<Asset_Context_Pending__c> pendingToUpsert = new List<Asset_Context_Pending__c>();

        // Find the latest session per matched EndUser in one query.
        Map<Id, Id> latestSessionByEndUser = latestSessionsByEndUser(endUserIdByUid.values());

        for (String uid : assetIdByUid.keySet()) {
            String assetId = assetIdByUid.get(uid);
            Id endUserId = endUserIdByUid.get(uid);
            Id sessionId = endUserId == null ? null : latestSessionByEndUser.get(endUserId);

            if (sessionId != null) {
                sessionsToUpdate.add(new MessagingSession(Id = sessionId, Asset_Id__c = assetId));
            } else {
                pendingToUpsert.add(new Asset_Context_Pending__c(UID__c = uid, Asset_Id__c = assetId));
            }
        }

        if (!sessionsToUpdate.isEmpty()) {
            Database.update(sessionsToUpdate, false);
        }
        if (!pendingToUpsert.isEmpty()) {
            Database.upsert(pendingToUpsert, Asset_Context_Pending__c.UID__c, false);
        }
    }

    /**
     * MessagingSession after-insert path: for freshly created sessions, resolve
     * the visitor UID from the EndUser platform key and stamp Asset_Id__c from
     * any stashed pending mapping. Consumed mappings are deleted.
     *
     * @param newSessions Trigger.new MessagingSession records
     */
    public static void stampFromPending(List<MessagingSession> newSessions) {
        if (newSessions == null || newSessions.isEmpty()) {
            return;
        }

        Set<Id> endUserIds = new Set<Id>();
        for (MessagingSession session : newSessions) {
            if (session.MessagingEndUserId != null) {
                endUserIds.add(session.MessagingEndUserId);
            }
        }
        if (endUserIds.isEmpty()) {
            return;
        }

        // Map EndUser -> UID via the platform key.
        Map<Id, String> uidByEndUser = new Map<Id, String>();
        for (MessagingEndUser eu : [
            SELECT Id, MessagingPlatformKey
            FROM MessagingEndUser
            WHERE Id IN :endUserIds
        ]) {
            String uid = extractUid(eu.MessagingPlatformKey);
            if (uid != null) {
                uidByEndUser.put(eu.Id, uid);
            }
        }
        if (uidByEndUser.isEmpty()) {
            return;
        }

        // Fetch stashed mappings for the resolved UIDs.
        Map<String, Asset_Context_Pending__c> pendingByUid = new Map<String, Asset_Context_Pending__c>();
        for (Asset_Context_Pending__c pending : [
            SELECT Id, UID__c, Asset_Id__c
            FROM Asset_Context_Pending__c
            WHERE UID__c IN :uidByEndUser.values()
        ]) {
            pendingByUid.put(pending.UID__c, pending);
        }
        if (pendingByUid.isEmpty()) {
            return;
        }

        List<MessagingSession> sessionsToUpdate = new List<MessagingSession>();
        List<Asset_Context_Pending__c> pendingToDelete = new List<Asset_Context_Pending__c>();

        for (MessagingSession session : newSessions) {
            String uid = uidByEndUser.get(session.MessagingEndUserId);
            if (uid == null) {
                continue;
            }
            Asset_Context_Pending__c pending = pendingByUid.get(uid);
            if (pending == null) {
                continue;
            }
            sessionsToUpdate.add(new MessagingSession(Id = session.Id, Asset_Id__c = pending.Asset_Id__c));
            pendingToDelete.add(pending);
        }

        if (!sessionsToUpdate.isEmpty()) {
            Database.update(sessionsToUpdate, false);
        }
        if (!pendingToDelete.isEmpty()) {
            Database.delete(pendingToDelete, false);
        }
    }

    /**
     * @param uids visitor UIDs to resolve
     * @return EndUser Id keyed by UID for the matching MessagingEndUser records
     */
    private static Map<String, Id> endUserIdsForUids(Set<String> uids) {
        Set<String> platformKeys = new Set<String>();
        Map<String, String> uidByPlatformKey = new Map<String, String>();
        for (String uid : uids) {
            String key = PLATFORM_KEY_PREFIX + uid;
            platformKeys.add(key);
            uidByPlatformKey.put(key, uid);
        }

        Map<String, Id> endUserIdByUid = new Map<String, Id>();
        for (MessagingEndUser eu : [
            SELECT Id, MessagingPlatformKey
            FROM MessagingEndUser
            WHERE MessagingPlatformKey IN :platformKeys
        ]) {
            String uid = uidByPlatformKey.get(eu.MessagingPlatformKey);
            if (uid != null) {
                endUserIdByUid.put(uid, eu.Id);
            }
        }
        return endUserIdByUid;
    }

    /**
     * @param endUserIds EndUser Ids to find sessions for
     * @return latest MessagingSession Id keyed by EndUser Id
     */
    private static Map<Id, Id> latestSessionsByEndUser(List<Id> endUserIds) {
        Map<Id, Id> latestByEndUser = new Map<Id, Id>();
        if (endUserIds == null || endUserIds.isEmpty()) {
            return latestByEndUser;
        }
        // Ordered newest-first; first seen per EndUser wins.
        for (MessagingSession session : [
            SELECT Id, MessagingEndUserId
            FROM MessagingSession
            WHERE MessagingEndUserId IN :endUserIds
            ORDER BY CreatedDate DESC
        ]) {
            if (!latestByEndUser.containsKey(session.MessagingEndUserId)) {
                latestByEndUser.put(session.MessagingEndUserId, session.Id);
            }
        }
        return latestByEndUser;
    }

    /**
     * @param platformKey MessagingEndUser.MessagingPlatformKey
     * @return the UID segment after 'uid:', or null when absent
     */
    private static String extractUid(String platformKey) {
        if (String.isBlank(platformKey) || !platformKey.contains('uid:')) {
            return null;
        }
        String uid = platformKey.substringAfter('uid:');
        return String.isBlank(uid) ? null : uid;
    }
}

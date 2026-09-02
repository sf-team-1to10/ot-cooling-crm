public with sharing class OTMsSessionResolver {
    @AuraEnabled(cacheable=true)
    public static Id getCaseId(Id recordId) {
        if (recordId == null) {
            return null;
        }
        String prefix = String.valueOf(recordId).substring(0, 3);
        if (prefix == '500') {
            return recordId;
        }
        if (prefix == '0Mw') {
            List<MessagingSession> sessions = [
                SELECT CaseId FROM MessagingSession
                WHERE Id = :recordId WITH USER_MODE LIMIT 1
            ];
            return sessions.isEmpty() ? null : sessions[0].CaseId;
        }
        return null;
    }
}

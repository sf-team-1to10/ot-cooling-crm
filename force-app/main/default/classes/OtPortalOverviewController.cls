/**
 * Read-only controller for the otPortalOverview dashboard (Phase 2).
 *
 * All queries are scoped to the running portal user's own Account via
 * Contact.AccountId — same pattern as OTMyAssetsController and
 * OtTrendAlertCardController. WITH USER_MODE + Security.stripInaccessible
 * enforces FLS/CRUD throughout.
 */
public with sharing class OtPortalOverviewController {

    @AuraEnabled(cacheable=true)
    public static OverviewSummary getOverviewSummary() {
        Id accountId = resolveRunningUserAccountId();
        if (accountId == null) {
            return emptyOverviewSummary();
        }

        OverviewSummary summary = new OverviewSummary();
        summary.totalAssets          = 0;
        summary.attentionAssets      = 0;
        summary.unacknowledgedAlerts = 0;
        summary.openCases            = 0;

        try {
            summary.totalAssets = [
                SELECT COUNT() FROM Asset
                WHERE AccountId = :accountId
                WITH USER_MODE
            ];
        } catch (Exception e) { /* FLS/sharing restriction — return 0 */ }

        try {
            // Latest_Trend_Flag__c is a Text field — exact string match required.
            summary.attentionAssets = [
                SELECT COUNT() FROM Asset
                WHERE AccountId = :accountId
                  AND Latest_Trend_Flag__c IN ('주의', '이상')
                WITH USER_MODE
            ];
        } catch (Exception e) { /* FLS/sharing restriction — return 0 */ }

        try {
            summary.unacknowledgedAlerts = [
                SELECT COUNT() FROM Customer_Alert__c
                WHERE Account__c = :accountId
                  AND Status__c = 'Active - Unacknowledged'
                WITH USER_MODE
            ];
        } catch (Exception e) { /* FLS/sharing restriction — return 0 */ }

        try {
            summary.openCases = [
                SELECT COUNT() FROM Case
                WHERE AccountId = :accountId
                  AND IsClosed = false
                WITH USER_MODE
            ];
        } catch (Exception e) { /* FLS/sharing restriction — return 0 */ }

        return summary;
    }

    @AuraEnabled(cacheable=true)
    public static List<AlertView> getRecentAlerts(Integer limitCount) {
        try {
            Id accountId = resolveRunningUserAccountId();
            if (accountId == null) {
                return new List<AlertView>();
            }

            Integer safeLimit = Math.min(limitCount == null ? 5 : limitCount, 20);

            List<Customer_Alert__c> alerts = [
                SELECT Id, Priority__c, Status__c, Message__c,
                       Started_At__c, Asset__r.Name
                FROM Customer_Alert__c
                WHERE Account__c = :accountId
                WITH USER_MODE
                ORDER BY Started_At__c DESC NULLS LAST
                LIMIT :safeLimit
            ];

            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.READABLE,
                alerts
            );
            List<Customer_Alert__c> accessible =
                (List<Customer_Alert__c>) decision.getRecords();

            List<AlertView> views = new List<AlertView>();
            for (Customer_Alert__c a : accessible) {
                AlertView view   = new AlertView();
                view.alertId     = a.Id;
                view.priority    = a.Priority__c;
                view.status      = a.Status__c;
                view.message     = a.Message__c;
                view.startedAt   = a.Started_At__c;
                view.assetName   = a.Asset__r != null ? a.Asset__r.Name : null;
                views.add(view);
            }
            return views;

        } catch (Exception e) {
            throw new AuraHandledException('알림 데이터를 불러오는 중 오류가 발생했습니다.');
        }
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    private static OverviewSummary emptyOverviewSummary() {
        OverviewSummary s        = new OverviewSummary();
        s.totalAssets            = 0;
        s.attentionAssets        = 0;
        s.unacknowledgedAlerts   = 0;
        s.openCases              = 0;
        return s;
    }

    /**
     * Duplicated from OTMyAssetsController — per-controller pattern used
     * throughout this codebase (same duplication exists in OtTrendAlertCardController).
     */
    private static Id resolveRunningUserAccountId() {
        List<User> users = [
            SELECT Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH USER_MODE
            LIMIT 1
        ];
        if (users.isEmpty() || users[0].Contact == null) {
            return null;
        }
        return users[0].Contact.AccountId;
    }

    // ── inner DTOs ────────────────────────────────────────────────────────────

    public class OverviewSummary {
        @AuraEnabled public Integer totalAssets;
        @AuraEnabled public Integer attentionAssets;
        @AuraEnabled public Integer unacknowledgedAlerts;
        @AuraEnabled public Integer openCases;
    }

    public class AlertView {
        @AuraEnabled public Id       alertId;
        @AuraEnabled public String   priority;
        @AuraEnabled public String   status;
        @AuraEnabled public String   message;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public String   assetName;
    }
}

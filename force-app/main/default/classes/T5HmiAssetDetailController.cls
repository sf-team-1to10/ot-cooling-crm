/**
 * Controller for the "자산 상세" (Asset Detail) HMI page — 단일 자산의
 * 상세 정보·활성 알림·정비 이력·보증/SLA·제품 이미지를 한 번에 반환한다.
 * 계정 스코핑은 T5HmiAssetHomeController와 동일 패턴(로그인 사용자의
 * Contact.AccountId 기준).
 */
public with sharing class T5HmiAssetDetailController {

    /**
     * 자산 상세 페이지에 필요한 전체 데이터를 한 번에 반환한다.
     * @param assetId 조회할 Asset의 Id.
     * @return AssetDetailData, 또는 로그인 사용자에게 연결된 Account가 없으면 null.
     */
    @AuraEnabled(cacheable=true)
    public static AssetDetailData getAssetDetail(Id assetId) {
        try {
            Id accountId = resolveRunningUserAccountId();
            if (accountId == null || assetId == null) {
                return null;
            }

            // ── Asset ───────────────────────────────────────────────────
            List<Asset> assets = Security.stripInaccessible(
                AccessType.READABLE,
                [
                    SELECT Id, Name, SerialNumber, InstallDate, Status, Site_Location__c,
                           Applied_Revision__c, Next_Inspection_Date__c, Open_Items_Summary__c,
                           Latest_Trend_Flag__c, Latest_Gauges_JSON__c,
                           Product2Id, Product2.Name, Product2.Asset_Type_Label__c
                    FROM Asset
                    WHERE Id = :assetId AND AccountId = :accountId
                    WITH USER_MODE
                    LIMIT 1
                ]
            ).getRecords();
            if (assets.isEmpty()) {
                return null;
            }
            Asset ast = assets[0];

            // ── Active Alert ────────────────────────────────────────────
            List<Customer_Alert__c> alerts = Security.stripInaccessible(
                AccessType.READABLE,
                [
                    SELECT Id, Priority__c, Category_Label__c, Alarm_Tag__c, Message__c,
                           Current_Value_Text__c, Normal_Range_Text__c, Current_Value__c,
                           Envelope_Min__c, Envelope_Max__c, Started_At__c, Status__c,
                           Acknowledged_At__c, Recommended_Action__c
                    FROM Customer_Alert__c
                    WHERE Asset__c = :assetId AND Status__c != 'Resolved'
                    WITH USER_MODE
                    ORDER BY Started_At__c DESC
                    LIMIT 1
                ]
            ).getRecords();

            // ── Work Order History ──────────────────────────────────────
            List<WorkOrder> workOrders = Security.stripInaccessible(
                AccessType.READABLE,
                [
                    SELECT Id, Subject, EndDate, Status, WorkOrderNumber
                    FROM WorkOrder
                    WHERE AssetId = :assetId AND Status = 'Completed'
                    WITH USER_MODE
                    ORDER BY EndDate DESC
                    LIMIT 10
                ]
            ).getRecords();

            // ── Product Image ───────────────────────────────────────────
            String imageUrl = null;
            if (ast.Product2Id != null) {
                try {
                    List<ContentDocumentLink> links = Security.stripInaccessible(
                        AccessType.READABLE,
                        [
                            SELECT ContentDocument.LatestPublishedVersionId
                            FROM ContentDocumentLink
                            WHERE LinkedEntityId = :ast.Product2Id
                            WITH USER_MODE
                            LIMIT 1
                        ]
                    ).getRecords();
                    if (!links.isEmpty() && links[0].ContentDocument != null) {
                        imageUrl = '/sfc/servlet.shepherd/version/download/' +
                            links[0].ContentDocument.LatestPublishedVersionId;
                    }
                } catch (Exception ignored) {
                    // ContentDocumentLink may not be accessible to portal users
                }
            }

            // ── Entitlement (Warranty / SLA) ────────────────────────────
            List<Entitlement> entitlements = new List<Entitlement>();
            try {
                entitlements = Security.stripInaccessible(
                    AccessType.READABLE,
                    [
                        SELECT Id, EndDate, SlaProcess.Name, Status
                        FROM Entitlement
                        WHERE AssetId = :assetId AND Status = 'Active'
                        WITH USER_MODE
                        ORDER BY EndDate DESC
                        LIMIT 1
                    ]
                ).getRecords();
            } catch (Exception ignored) {
                // Entitlement may not be accessible to portal users
            }

            // ── Last Maintenance Date ───────────────────────────────────
            Date lastMaintenanceDate = null;
            if (!workOrders.isEmpty() && workOrders[0].EndDate != null) {
                lastMaintenanceDate = workOrders[0].EndDate.date();
            }

            // ── Build DTOs ──────────────────────────────────────────────
            AssetDetailView assetView = new AssetDetailView();
            assetView.assetId = ast.Id;
            assetView.name = ast.Name;
            assetView.serialNumber = (String) ast.get('SerialNumber');
            assetView.installDate = (Date) ast.get('InstallDate');
            assetView.status = ast.Status;
            assetView.siteLocation = ast.Site_Location__c;
            assetView.appliedRevision = (String) ast.get('Applied_Revision__c');
            assetView.nextInspectionDate = ast.Next_Inspection_Date__c;
            assetView.productName = ast.Product2 == null ? null : ast.Product2.Name;
            assetView.assetTypeLabel = ast.Product2 == null ? null : ast.Product2.Asset_Type_Label__c;
            assetView.imageUrl = imageUrl;
            assetView.latestTrendFlag = (String) ast.get('Latest_Trend_Flag__c');
            assetView.openItemsSummary = ast.Open_Items_Summary__c;
            assetView.lastMaintenanceDate = lastMaintenanceDate;
            assetView.latestGaugesJson = (String) ast.get('Latest_Gauges_JSON__c');

            AlertDetailView alertView = null;
            if (!alerts.isEmpty()) {
                Customer_Alert__c a = alerts[0];
                alertView = new AlertDetailView();
                alertView.alertId = a.Id;
                alertView.priority = a.Priority__c;
                alertView.categoryLabel = a.Category_Label__c;
                alertView.alarmTag = a.Alarm_Tag__c;
                alertView.message = a.Message__c;
                alertView.currentValueText = a.Current_Value_Text__c;
                alertView.normalRangeText = a.Normal_Range_Text__c;
                alertView.currentValue = a.Current_Value__c;
                alertView.envelopeMin = a.Envelope_Min__c;
                alertView.envelopeMax = a.Envelope_Max__c;
                alertView.startedAt = a.Started_At__c;
                alertView.status = a.Status__c;
                alertView.recommendedAction = a.Recommended_Action__c;
            }

            List<HistoryEntry> history = new List<HistoryEntry>();
            for (WorkOrder wo : workOrders) {
                HistoryEntry h = new HistoryEntry();
                h.title = wo.Subject;
                h.entryDate = wo.EndDate != null ? wo.EndDate.date() : null;
                h.entryType = 'Work Order';
                h.workOrderNumber = wo.WorkOrderNumber;
                history.add(h);
            }

            EntitlementView entitlementView = null;
            if (!entitlements.isEmpty()) {
                Entitlement ent = entitlements[0];
                entitlementView = new EntitlementView();
                entitlementView.endDate = ent.EndDate;
                entitlementView.slaProcessName = ent.SlaProcess != null ? ent.SlaProcess.Name : null;
                entitlementView.status = ent.Status;
            }

            AssetDetailData result = new AssetDetailData();
            result.asset = assetView;
            result.alert = alertView;
            result.history = history;
            result.entitlement = entitlementView;
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('자산 상세 데이터를 불러오는 중 오류가 발생했습니다.');
        }
    }

    /**
     * "알람 확인" 버튼 — Customer_Alert__c.Status__c만 Acknowledged로 바꾼다.
     * T5HmiAssetHomeController.acknowledgeAlert과 동일 패턴.
     * @param alertId 확인 처리할 Customer_Alert__c Id.
     * @return 갱신된 AlertDetailView.
     */
    @AuraEnabled
    public static AlertDetailView acknowledgeAlert(Id alertId) {
        try {
            Id accountId = resolveRunningUserAccountId();
            if (accountId == null || alertId == null) {
                throw new AuraHandledException('처리할 수 없는 요청입니다.');
            }

            List<Customer_Alert__c> alerts = [
                SELECT Id, Status__c, Asset__r.AccountId
                FROM Customer_Alert__c
                WHERE Id = :alertId
                WITH USER_MODE
                LIMIT 1
            ];
            if (alerts.isEmpty() || alerts[0].Asset__r.AccountId != accountId) {
                throw new AuraHandledException('해당 알림을 찾을 수 없습니다.');
            }

            if (alerts[0].Status__c == 'Active - Unacknowledged') {
                T5HmiAlertAckWriter.write(alerts[0].Id);
            }

            Customer_Alert__c refreshed = [
                SELECT Id, Priority__c, Category_Label__c, Alarm_Tag__c, Message__c,
                       Current_Value_Text__c, Normal_Range_Text__c, Current_Value__c,
                       Envelope_Min__c, Envelope_Max__c, Started_At__c, Status__c,
                       Recommended_Action__c
                FROM Customer_Alert__c
                WHERE Id = :alertId
                WITH USER_MODE
                LIMIT 1
            ];

            AlertDetailView v = new AlertDetailView();
            v.alertId = refreshed.Id;
            v.priority = refreshed.Priority__c;
            v.categoryLabel = refreshed.Category_Label__c;
            v.alarmTag = refreshed.Alarm_Tag__c;
            v.message = refreshed.Message__c;
            v.currentValueText = refreshed.Current_Value_Text__c;
            v.normalRangeText = refreshed.Normal_Range_Text__c;
            v.currentValue = refreshed.Current_Value__c;
            v.envelopeMin = refreshed.Envelope_Min__c;
            v.envelopeMax = refreshed.Envelope_Max__c;
            v.startedAt = refreshed.Started_At__c;
            v.status = refreshed.Status__c;
            v.recommendedAction = refreshed.Recommended_Action__c;
            return v;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('알람 확인 처리 중 오류가 발생했습니다.');
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

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

    // ─── DTOs ────────────────────────────────────────────────────────────

    public class AssetDetailData {
        @AuraEnabled public AssetDetailView asset;
        @AuraEnabled public AlertDetailView alert;
        @AuraEnabled public List<HistoryEntry> history;
        @AuraEnabled public EntitlementView entitlement;
    }

    public class AssetDetailView {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String name;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public Date installDate;
        @AuraEnabled public String status;
        @AuraEnabled public String siteLocation;
        @AuraEnabled public String appliedRevision;
        @AuraEnabled public Date nextInspectionDate;
        @AuraEnabled public String productName;
        @AuraEnabled public String assetTypeLabel;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String latestTrendFlag;
        @AuraEnabled public Decimal openItemsSummary;
        @AuraEnabled public Date lastMaintenanceDate;
        @AuraEnabled public String latestGaugesJson;
    }

    public class AlertDetailView {
        @AuraEnabled public Id alertId;
        @AuraEnabled public String priority;
        @AuraEnabled public String categoryLabel;
        @AuraEnabled public String alarmTag;
        @AuraEnabled public String message;
        @AuraEnabled public String currentValueText;
        @AuraEnabled public String normalRangeText;
        @AuraEnabled public Decimal currentValue;
        @AuraEnabled public Decimal envelopeMin;
        @AuraEnabled public Decimal envelopeMax;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public String status;
        @AuraEnabled public String recommendedAction;
    }

    public class HistoryEntry {
        @AuraEnabled public String title;
        @AuraEnabled public Date entryDate;
        @AuraEnabled public String entryType;
        @AuraEnabled public String workOrderNumber;
    }

    public class EntitlementView {
        @AuraEnabled public Date endDate;
        @AuraEnabled public String slaProcessName;
        @AuraEnabled public String status;
    }
}

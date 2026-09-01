/**
 * Controller for the "고객 운영 콘솔" HMI 홈 화면(T5-07 확장, 고객운영홈_HMI.html
 * 1:1 이식). 계정 스코핑은 OTMyAssetsController/OtTrendAlertCardController와
 * 동일 패턴(로그인 사용자의 Contact.AccountId 기준) — 로그인 기반 포털
 * 아키텍처 결정(2026-08-30)을 그대로 따른다.
 *
 * ⚠ 데모 데이터 경계: 계측값(Current PV 등)·알람 라이프사이클은 실제로는
 * BMS/IoT·SCADA/CMMS가 담당한다. 이 컨트롤러는 Salesforce에 이미 있는
 * Asset·Product2·WorkOrder·Customer_Alert__c만 읽고 쓴다 — 실시간 IoT 연동은
 * 하지 않는다(요구사항 18).
 */
public with sharing class T5HmiAssetHomeController {
    private static final Set<String> ATTENTION_TREND_FLAGS = new Set<String>{ '주의', '이상' };

    /**
     * 홈 화면 전체 데이터(현장 개요 + 자산 목록 + 활성 배너 알림 1건)를 한 번에 반환한다.
     * @return AssetHomeData, 또는 로그인 사용자에게 연결된 Account가 없으면 빈 데이터.
     */
    @AuraEnabled(cacheable=true)
    public static AssetHomeData getAssetHomeData() {
        try {
            Id accountId = resolveRunningUserAccountId();
            AssetHomeData result = new AssetHomeData();
            if (accountId == null) {
                return result;
            }

            List<Asset> assets = [
                SELECT Id, Name, Status, Site_Location__c, Next_Inspection_Date__c,
                       Open_Items_Summary__c, Latest_Trend_Flag__c,
                       Product2Id, Product2.Name, Product2.Asset_Type_Label__c,
                       Product2.Asset_Category__c, Product2.Family
                FROM Asset
                WHERE AccountId = :accountId
                WITH USER_MODE
                ORDER BY Name
            ];
            if (assets.isEmpty()) {
                return result;
            }

            Set<Id> assetIds = new Set<Id>();
            Set<Id> productIds = new Set<Id>();
            for (Asset a : assets) {
                assetIds.add(a.Id);
                if (a.Product2Id != null) {
                    productIds.add(a.Product2Id);
                }
            }

            Map<Id, Date> lastMaintenanceByAsset = resolveLastMaintenanceDates(assetIds);
            Map<Id, String> imageUrlByProduct = resolveProductImageUrls(productIds);

            Integer normalCount = 0;
            Integer advisoryCount = 0;
            Integer maintenanceCount = 0;
            Integer offlineCount = 0;

            List<AssetHmiView> views = new List<AssetHmiView>();
            for (Asset a : assets) {
                AssetHmiView v = new AssetHmiView();
                v.assetId = a.Id;
                v.name = a.Name;
                v.type = a.Product2 == null ? null : a.Product2.Asset_Type_Label__c;
                v.cat = a.Product2 == null ? null : a.Product2.Asset_Category__c;
                v.family = a.Product2 == null ? null : a.Product2.Family;
                v.loc = a.Site_Location__c;
                v.imageUrl = (a.Product2Id != null) ? imageUrlByProduct.get(a.Product2Id) : null;

                Boolean advisory = ATTENTION_TREND_FLAGS.contains(a.Latest_Trend_Flag__c);
                v.health = advisory ? 'Advisory' : 'Healthy';
                v.op = resolveOperatingState(a.Status);
                v.cond = buildConditionText(advisory, a.Open_Items_Summary__c);
                v.lastMaintenance = lastMaintenanceByAsset.get(a.Id);
                v.nextMaintenance = a.Next_Inspection_Date__c;

                views.add(v);

                if (v.op == 'Maintenance') {
                    maintenanceCount++;
                } else if (v.op == 'Offline') {
                    offlineCount++;
                } else if (advisory) {
                    advisoryCount++;
                } else {
                    normalCount++;
                }
            }
            result.assets = views;
            result.totalCount = views.size();
            result.normalCount = normalCount;
            result.advisoryCount = advisoryCount;
            result.maintenanceCount = maintenanceCount;
            result.offlineCount = offlineCount;
            result.siteLabel = resolveSiteLabel(assets);
            result.lastUpdatedText = Datetime.now().format('HH:mm');
            result.activeAlert = resolveActiveAlert(assetIds);

            return result;
        } catch (Exception e) {
            throw new AuraHandledException('자산 홈 데이터를 불러오는 중 오류가 발생했습니다.');
        }
    }

    /**
     * "알람 확인" 버튼 — Customer_Alert__c.Status__c만 Acknowledged로 바꾼다.
     * Case/Work Order는 만들거나 닫지 않는다(요구사항 9).
     * @param alertId 확인 처리할 Customer_Alert__c Id.
     * @return 갱신된 AlertView.
     */
    @AuraEnabled
    public static AlertView acknowledgeAlert(Id alertId) {
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
                // 위에서 이미 "이 알림이 호출자 계정 소유의 Asset에 속한다"는
                // 검증(WITH USER_MODE 조회 + accountId 일치)을 마쳤다. 그런데도
                // 실제 update는 record-level 공유 문제로 막힌다 — Customer_Alert__c는
                // Asset의 Master-Detail 자식(ControlledByParent)인데, 포털 사용자가
                // 부모 Asset에 대해 갖는 접근 등급이 Read뿐이라 자식도 Read까지만
                // 상속되고, Edit은 상속이 안 된다(INSUFFICIENT_ACCESS_ON_
                // CROSS_REFERENCE_ENTITY, 2026-08-30 확인 — Asset에 Edit 객체
                // 권한을 부여해도 동일). Asset에 Edit 권한을 넓히는 대신, 이미
                // 소유권 검증이 끝난 레코드 1건·필드 2개(Status__c,
                // Acknowledged_At__c)에 한정해서만 시스템 컨텍스트로 쓴다 —
                // WorkOrderLineItem 우회 때 기각했던 "통째로 without sharing"과는
                // 다르게, 인가 검사를 우회하지 않고 그 결과만 좁게 적용하는 것.
                T5HmiAlertAckWriter.write(alerts[0].Id);
            }

            return toAlertView(
                [
                    SELECT Id, Priority__c, Category_Label__c, Alarm_Tag__c, Message__c,
                           Current_Value_Text__c, Normal_Range_Text__c, Current_Value__c,
                           Envelope_Min__c, Envelope_Max__c, Started_At__c, Status__c,
                           Recommended_Action__c, Asset__c, Asset__r.Name, Asset__r.Site_Location__c,
                           Asset__r.Product2.Asset_Type_Label__c
                    FROM Customer_Alert__c
                    WHERE Id = :alertId
                    WITH USER_MODE
                    LIMIT 1
                ][0]
            );
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

    /** WorkOrder는 포털에서 조회 가능(WorkOrderLineItem과 달리 라이선스 제약 없음, 2026-08-30 확인).
     *  완료일은 WorkOrder.CompletedDate가 이 org에 없어서 EndDate(작업 종료일)로 대체. */
    private static Map<Id, Date> resolveLastMaintenanceDates(Set<Id> assetIds) {
        Map<Id, Date> result = new Map<Id, Date>();
        for (WorkOrder wo : [
            SELECT AssetId, EndDate
            FROM WorkOrder
            WHERE AssetId IN :assetIds AND Status = 'Completed' AND EndDate != null
            WITH USER_MODE
            ORDER BY EndDate DESC
        ]) {
            if (!result.containsKey(wo.AssetId)) {
                result.put(wo.AssetId, wo.EndDate.date());
            }
        }
        return result;
    }

    /**
     * Product2에 첨부된 파일(대표 이미지)의 다운로드 URL. 파일이 없으면 null —
     * LWC가 이 경우 목업에 이미 있던 SILHOUETTE placeholder를 보여준다
     * (요구사항 13). 이미지는 자산 단위가 아니라 제품(모델) 단위로 공유한다.
     */
    private static Map<Id, String> resolveProductImageUrls(Set<Id> productIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (productIds.isEmpty()) {
            return result;
        }
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId, ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :productIds
            WITH USER_MODE
        ]) {
            if (!result.containsKey(link.LinkedEntityId) && link.ContentDocument != null) {
                result.put(
                    link.LinkedEntityId,
                    '/sfc/servlet.shepherd/version/download/' + link.ContentDocument.LatestPublishedVersionId
                );
            }
        }
        return result;
    }

    private static String resolveOperatingState(String assetStatus) {
        if (assetStatus == null) {
            return 'Normal';
        }
        String lower = assetStatus.toLowerCase();
        if (lower.contains('maintenance') || lower.contains('정비')) {
            return 'Maintenance';
        }
        if (lower.contains('offline') || lower.contains('down') || lower.contains('통신')) {
            return 'Offline';
        }
        return 'Normal';
    }

    private static String buildConditionText(Boolean advisory, Decimal openItems) {
        if (!advisory) {
            return '정상 운전 중';
        }
        Integer open = openItems == null ? 0 : openItems.intValue();
        return open > 0
            ? '기준선 대비 이상 감지 · 미조치 ' + open + '건'
            : '기준선 대비 이상 감지';
    }

    private static String resolveSiteLabel(List<Asset> assets) {
        // 이 계정의 자산이 전부 같은 Site_Location__c 접두(Hall)를 쓴다는 전제 —
        // "Hall A · 3열" 형식에서 첫 " · " 앞부분만 뽑는다. 못 찾으면 기본 문구.
        for (Asset a : assets) {
            if (String.isNotBlank(a.Site_Location__c) && a.Site_Location__c.contains(' · ')) {
                String hall = a.Site_Location__c.substringBefore(' · ');
                return hall + ' · 냉각 자산 ' + assets.size() + '대';
            }
        }
        return '냉각 자산 ' + assets.size() + '대';
    }

    private static AlertView resolveActiveAlert(Set<Id> assetIds) {
        List<Customer_Alert__c> alerts = [
            SELECT Id, Priority__c, Category_Label__c, Alarm_Tag__c, Message__c,
                   Current_Value_Text__c, Normal_Range_Text__c, Current_Value__c,
                   Envelope_Min__c, Envelope_Max__c, Started_At__c, Status__c,
                   Recommended_Action__c, Asset__c, Asset__r.Name, Asset__r.Site_Location__c,
                   Asset__r.Product2.Asset_Type_Label__c
            FROM Customer_Alert__c
            WHERE Asset__c IN :assetIds AND Status__c != 'Resolved'
            WITH USER_MODE
            ORDER BY Started_At__c DESC
            LIMIT 1
        ];
        return alerts.isEmpty() ? null : toAlertView(alerts[0]);
    }

    private static AlertView toAlertView(Customer_Alert__c a) {
        AlertView v = new AlertView();
        v.alertId = a.Id;
        v.assetId = a.Asset__c;
        v.assetName = a.Asset__r != null ? a.Asset__r.Name : null;
        v.assetType = (a.Asset__r != null && a.Asset__r.Product2 != null) ? a.Asset__r.Product2.Asset_Type_Label__c : null;
        v.assetLoc = a.Asset__r != null ? a.Asset__r.Site_Location__c : null;
        v.priority = a.Priority__c;
        v.categoryLabel = a.Category_Label__c;
        v.alarmTag = a.Alarm_Tag__c;
        v.message = a.Message__c;
        v.currentValueText = a.Current_Value_Text__c;
        v.normalRangeText = a.Normal_Range_Text__c;
        v.currentValue = a.Current_Value__c;
        v.envelopeMin = a.Envelope_Min__c;
        v.envelopeMax = a.Envelope_Max__c;
        v.startedAt = a.Started_At__c;
        v.status = a.Status__c;
        v.recommendedAction = a.Recommended_Action__c;
        v.acknowledged = a.Status__c != 'Active - Unacknowledged';
        return v;
    }

    // ─── DTOs ────────────────────────────────────────────────────────────

    public class AssetHomeData {
        @AuraEnabled public String siteLabel;
        @AuraEnabled public String lastUpdatedText;
        @AuraEnabled public Integer totalCount = 0;
        @AuraEnabled public Integer normalCount = 0;
        @AuraEnabled public Integer advisoryCount = 0;
        @AuraEnabled public Integer maintenanceCount = 0;
        @AuraEnabled public Integer offlineCount = 0;
        @AuraEnabled public Integer serviceCount = 0;
        @AuraEnabled public List<AssetHmiView> assets = new List<AssetHmiView>();
        @AuraEnabled public AlertView activeAlert;
    }

    public class AssetHmiView {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String name;
        @AuraEnabled public String type;
        @AuraEnabled public String cat;
        @AuraEnabled public String family;
        @AuraEnabled public String loc;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String health; // Healthy | Advisory
        @AuraEnabled public String op;     // Normal | Maintenance | Offline
        @AuraEnabled public String cond;
        @AuraEnabled public Date lastMaintenance;
        @AuraEnabled public Date nextMaintenance;
        @AuraEnabled public Boolean serviceInProgress = false;
    }

    public class AlertView {
        @AuraEnabled public Id alertId;
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String assetType;
        @AuraEnabled public String assetLoc;
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
        @AuraEnabled public Boolean acknowledged;
    }
}

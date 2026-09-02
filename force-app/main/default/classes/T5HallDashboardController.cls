/**
 * Hall A 운영 대시보드 데이터 공급 컨트롤러 (T5-09).
 * Hall A 냉각장비(CDU-A-*) 전체를 집계해 각 자산의 최신 점검 Trend 상태와
 * 예방정비 진행률을 한 화면에서 보여주기 위한 데이터를 반환한다.
 * Service Console 홈의 t5HallDashboard LWC가 @wire로 소비한다.
 */
public with sharing class T5HallDashboardController {

    private static final String HALL_A_PREFIX = 'CDU-A-%';
    private static final String INSPECTION_ROLE = '점검';
    private static final String PREVENTIVE_SUBTYPE = '예방정비';
    private static final Set<String> DONE_WO_STATUS = new Set<String>{ 'Completed', 'Closed' };
    private static final String UNINSPECTED = '미점검';

    /**
     * Hall A 대시보드 집계 데이터를 반환한다.
     * @return 자산별 최신 Trend 상태 + 상태별 카운트 + 예방정비 진행률
     */
    @AuraEnabled(cacheable=true)
    public static HallSummary getHallSummary() {
        HallSummary summary = new HallSummary();

        // 1) Hall A 자산 목록
        List<Asset> assets = [
            SELECT Id, Name, Status
            FROM Asset
            WHERE Name LIKE :HALL_A_PREFIX
            WITH USER_MODE
            ORDER BY Name
        ];
        if (assets.isEmpty()) {
            return summary;
        }

        // 2) 각 자산의 최신 점검 WOLI Trend (자산당 1건, 최신순)
        Map<Id, String> latestTrendByAsset = new Map<Id, String>();
        for (WorkOrderLineItem w : [
            SELECT AssetId, Trend_Flag__c
            FROM WorkOrderLineItem
            WHERE Asset.Name LIKE :HALL_A_PREFIX
              AND Line_Item_Role__c = :INSPECTION_ROLE
              AND Trend_Flag__c != null
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ]) {
            if (!latestTrendByAsset.containsKey(w.AssetId)) {
                latestTrendByAsset.put(w.AssetId, w.Trend_Flag__c);
            }
        }

        // 3) 자산별 행 + 상태 카운트 조립
        for (Asset a : assets) {
            String trend = latestTrendByAsset.containsKey(a.Id)
                ? latestTrendByAsset.get(a.Id)
                : UNINSPECTED;

            AssetRow row = new AssetRow();
            row.id = a.Id;
            row.name = a.Name;
            row.assetStatus = a.Status;
            row.trend = trend;
            summary.assets.add(row);

            summary.incrementCount(trend);
        }
        summary.totalAssets = assets.size();

        // 4) 예방정비 진행률 (Hall A 예방정비 WO 중 완료 비율)
        Integer preventiveTotal = 0;
        Integer preventiveDone = 0;
        for (WorkOrder wo : [
            SELECT Status
            FROM WorkOrder
            WHERE Asset.Name LIKE :HALL_A_PREFIX
              AND Work_Subtype__c = :PREVENTIVE_SUBTYPE
            WITH USER_MODE
        ]) {
            preventiveTotal++;
            if (DONE_WO_STATUS.contains(wo.Status)) {
                preventiveDone++;
            }
        }
        summary.preventiveTotal = preventiveTotal;
        summary.preventiveDone = preventiveDone;
        summary.preventiveProgress = preventiveTotal == 0
            ? 0
            : (Integer) Math.round(100.0 * preventiveDone / preventiveTotal);

        return summary;
    }

    // ─── DTOs ────────────────────────────────────────────────────────────

    public class HallSummary {
        @AuraEnabled public Integer totalAssets = 0;
        @AuraEnabled public Integer normalCount = 0;
        @AuraEnabled public Integer warningCount = 0;
        @AuraEnabled public Integer criticalCount = 0;
        @AuraEnabled public Integer uninspectedCount = 0;
        @AuraEnabled public Integer preventiveTotal = 0;
        @AuraEnabled public Integer preventiveDone = 0;
        @AuraEnabled public Integer preventiveProgress = 0;
        @AuraEnabled public List<AssetRow> assets = new List<AssetRow>();

        void incrementCount(String trend) {
            if (trend == '정상') {
                normalCount++;
            } else if (trend == '주의') {
                warningCount++;
            } else if (trend == '이상') {
                criticalCount++;
            } else {
                uninspectedCount++;
            }
        }
    }

    public class AssetRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String assetStatus;
        @AuraEnabled public String trend;
    }
}
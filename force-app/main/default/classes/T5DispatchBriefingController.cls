/**
 * 출동 브리핑 Workbench 데이터 공급 컨트롤러 (S-02).
 * Case Id를 받아 (1) Hall A CDU 12대 유량 비교, (2) Priority 산정 근거,
 * (3) 현재 Case의 브리핑 본문·유사사례·승인 상태를 하나의 DTO로 묶어 반환한다.
 * 서정비가 한 화면에서 A-07과 나머지 11대를 비교하고 Priority를 승인/변경하는 용도.
 * Callable from the otDispatchBriefingWorkbench LWC via @wire.
 */
public with sharing class T5DispatchBriefingController {

    private static final String MEASUREMENT_FLOW = '유량';
    private static final String TREND_ABNORMAL = '이상';
    private static final String TREND_WARNING = '주의';
    private static final String JUDGE_FAIL = '불합격';
    private static final String ASSET_PREFIX = 'CDU-A-';

    /**
     * 현재 Case 기준으로 출동 브리핑 데이터를 조립한다.
     * @param caseId 조회 기준 Case Id
     * @return 12대 비교·Priority 근거·현재 Case 정보를 담은 DispatchBriefing
     */
    @AuraEnabled(cacheable=true)
    public static DispatchBriefing getBriefing(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id가 필요합니다.');
        }
        Case current = getCurrentCase(caseId);

        DispatchBriefing result = new DispatchBriefing();
        result.caseId = current.Id;
        result.caseNumber = current.CaseNumber;
        result.subject = current.Subject;
        result.priority = current.Priority;
        result.impactLevel = current.Impact_Level__c;
        result.briefingBody = current.Dispatch_Briefing__c;
        result.similarCasesSummary = current.Similar_Cases_Summary__c;
        result.targetAssetName = current.Asset?.Name;

        result.comparisons = buildComparisons();
        result.priorityRationale = buildPriorityRationale(result.comparisons, current);
        return result;
    }

    // ─── Current Case ────────────────────────────────────────────────────

    private static Case getCurrentCase(Id caseId) {
        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Priority, Impact_Level__c,
                   Dispatch_Briefing__c, Similar_Cases_Summary__c,
                   AssetId, Asset.Name
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            throw new AuraHandledException('Case를 찾을 수 없습니다: ' + caseId);
        }
        return cases[0];
    }

    // ─── 12대 유량 비교 ───────────────────────────────────────────────────

    /**
     * Hall A CDU 12대의 대표 유량 측정을 조립한다.
     * 대표값 규칙: Trend가 이상/주의인 측정이 있으면 그 중 가장 최근 것을,
     * 없으면 정상 측정 중 가장 최근 것을 대표로 삼는다. 이로써 회복 이력이
     * 있는 A-07도 장애 상태(이상)로 비교 테이블에 표시된다.
     */
    private static List<AssetComparison> buildComparisons() {
        // Asset별 Revision
        Map<Id, Asset> assetsById = new Map<Id, Asset>([
            SELECT Id, Name, Applied_Revision__c
            FROM Asset
            WHERE Name LIKE :(ASSET_PREFIX + '%')
            WITH USER_MODE
        ]);
        if (assetsById.isEmpty()) {
            return new List<AssetComparison>();
        }

        // Asset별 과거 불합격 이력 존재 여부
        Set<Id> failedAssetIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT WorkOrder.AssetId aid
            FROM WorkOrderLineItem
            WHERE Judgement__c = :JUDGE_FAIL
              AND WorkOrder.AssetId IN :assetsById.keySet()
            WITH USER_MODE
            GROUP BY WorkOrder.AssetId
        ]) {
            failedAssetIds.add((Id) ar.get('aid'));
        }

        // 유량 측정 전체 (최신순) — Asset별 대표값을 코드에서 선별
        Map<Id, WorkOrderLineItem> abnormalByAsset = new Map<Id, WorkOrderLineItem>();
        Map<Id, WorkOrderLineItem> normalByAsset = new Map<Id, WorkOrderLineItem>();
        for (WorkOrderLineItem w : [
            SELECT WorkOrder.AssetId, Measured_Value__c, Baseline_Value__c,
                   Drift_From_Baseline__c, Trend_Flag__c, CreatedDate
            FROM WorkOrderLineItem
            WHERE Measurement_Item_Code__c = :MEASUREMENT_FLOW
              AND WorkOrder.AssetId IN :assetsById.keySet()
              AND Measured_Value__c != null
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ]) {
            Id aid = w.WorkOrder.AssetId;
            Boolean isAbnormal = w.Trend_Flag__c == TREND_ABNORMAL || w.Trend_Flag__c == TREND_WARNING;
            if (isAbnormal) {
                if (!abnormalByAsset.containsKey(aid)) {
                    abnormalByAsset.put(aid, w);
                }
            } else if (!normalByAsset.containsKey(aid)) {
                normalByAsset.put(aid, w);
            }
        }

        List<AssetComparison> comparisons = new List<AssetComparison>();
        for (Asset a : assetsById.values()) {
            WorkOrderLineItem rep = abnormalByAsset.containsKey(a.Id)
                ? abnormalByAsset.get(a.Id)
                : normalByAsset.get(a.Id);

            AssetComparison c = new AssetComparison();
            c.assetId = a.Id;
            c.assetName = a.Name;
            c.appliedRevision = a.Applied_Revision__c;
            c.hasPastFailure = failedAssetIds.contains(a.Id);
            if (rep != null) {
                c.measuredValue = rep.Measured_Value__c;
                c.baselineValue = rep.Baseline_Value__c;
                c.driftFromBaseline = rep.Drift_From_Baseline__c;
                c.trendFlag = rep.Trend_Flag__c;
            }
            comparisons.add(c);
        }
        comparisons.sort();
        return comparisons;
    }

    // ─── Priority 산정 근거 ────────────────────────────────────────────────

    /**
     * 12대 비교 결과에서 대상 장비(가장 큰 하락폭)를 찾아 Priority 근거 5개 인자를 요약한다.
     * 값 자체는 규칙/Flow가 이미 산정했고, 여기서는 근거를 화면용으로 조립만 한다.
     */
    private static PriorityRationale buildPriorityRationale(List<AssetComparison> comparisons, Case current) {
        PriorityRationale r = new PriorityRationale();
        r.priority = current.Priority;

        AssetComparison worst = null;
        for (AssetComparison c : comparisons) {
            if (c.driftFromBaseline == null) {
                continue;
            }
            if (worst == null || c.driftFromBaseline < worst.driftFromBaseline) {
                worst = c;
            }
        }
        if (worst != null) {
            r.maxDriftAssetName = worst.assetName;
            r.maxDriftValue = worst.driftFromBaseline;
            r.hasPastFailure = worst.hasPastFailure;
        }
        r.comparedCount = comparisons.size();
        r.impactLevel = current.Impact_Level__c;
        return r;
    }

    // ─── DTOs ────────────────────────────────────────────────────────────

    public class DispatchBriefing {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String priority;
        @AuraEnabled public String impactLevel;
        @AuraEnabled public String briefingBody;
        @AuraEnabled public String similarCasesSummary;
        @AuraEnabled public String targetAssetName;
        @AuraEnabled public List<AssetComparison> comparisons = new List<AssetComparison>();
        @AuraEnabled public PriorityRationale priorityRationale;
    }

    public class AssetComparison implements Comparable {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String appliedRevision;
        @AuraEnabled public Decimal measuredValue;
        @AuraEnabled public Decimal baselineValue;
        @AuraEnabled public Decimal driftFromBaseline;
        @AuraEnabled public String trendFlag;
        @AuraEnabled public Boolean hasPastFailure;

        /**
         * 하락폭(Drift)이 큰 순으로 정렬한다. null은 뒤로.
         */
        public Integer compareTo(Object other) {
            AssetComparison o = (AssetComparison) other;
            if (driftFromBaseline == null && o.driftFromBaseline == null) {
                return 0;
            }
            if (driftFromBaseline == null) {
                return 1;
            }
            if (o.driftFromBaseline == null) {
                return -1;
            }
            if (driftFromBaseline < o.driftFromBaseline) {
                return -1;
            }
            if (driftFromBaseline > o.driftFromBaseline) {
                return 1;
            }
            return 0;
        }
    }

    public class PriorityRationale {
        @AuraEnabled public String priority;
        @AuraEnabled public String impactLevel;
        @AuraEnabled public String maxDriftAssetName;
        @AuraEnabled public Decimal maxDriftValue;
        @AuraEnabled public Boolean hasPastFailure;
        @AuraEnabled public Integer comparedCount;
    }
}

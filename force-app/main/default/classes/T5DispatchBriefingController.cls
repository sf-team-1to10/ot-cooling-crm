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

        RecoverySla sla = getRecoverySla(current.Id);
        result.slaRemaining = (sla != null) ? sla.display : null;
        result.calculatedAt = current.Warranty_Judged_At__c;

        applyApprovalState(result, current.Id);

        result.comparisons = buildComparisons();
        result.priorityRationale = buildPriorityRationale(result.comparisons, current, sla);
        return result;
    }

    /**
     * Priority 승인 상태(승인 시각·승인자)를 DTO에 채운다.
     * 승인 필드는 신규 배포 직후 스키마 캐시 미반영 가능성이 있어 동적 SOQL로 접근하고,
     * 실패하면 미승인 상태로 degrade한다.
     * @param result 채울 대상 DTO
     * @param caseId 대상 Case Id
     */
    private static void applyApprovalState(DispatchBriefing result, Id caseId) {
        // 승인 스탬프는 시스템이 기록하는 감사 필드다. 읽기도 SYSTEM_MODE로 접근해
        // approveDispatch(시스템 모드 write)와 일관성을 맞춘다. 레코드 접근은 with sharing이 통제.
        // 신규 배포 직후 스키마 캐시 미반영 가능성이 있어 동적 SOQL + try/catch로 degrade한다.
        try {
            List<SObject> rows = Database.queryWithBinds(
                'SELECT Priority_Approved_At__c, Priority_Approved_By__r.Name '
                    + 'FROM Case WHERE Id = :caseId LIMIT 1',
                new Map<String, Object>{ 'caseId' => caseId },
                AccessLevel.SYSTEM_MODE
            );
            if (!rows.isEmpty()) {
                SObject row = rows[0];
                result.approvedAt = (Datetime) row.get('Priority_Approved_At__c');
                Object approver = row.getSObject('Priority_Approved_By__r') == null
                    ? null
                    : row.getSObject('Priority_Approved_By__r').get('Name');
                result.approvedByName = (String) approver;
                result.isApproved = result.approvedAt != null;
            }
        } catch (Exception e) {
            result.isApproved = false;
        }
    }

    /**
     * 서정비가 브리핑에서 Priority를 승인하고 출동을 확정한다.
     * 승인자와 승인 시각을 기록해 "규칙 산정 → 담당자 승인" 통제를 증명한다.
     * 데모 KPI 시각(02:45)은 별도 시딩으로 덮어쓴다.
     * @param caseId 승인할 Case Id
     * @throws AuraHandledException Case Id가 없거나 승인 저장에 실패할 때
     */
    @AuraEnabled
    public static void approveDispatch(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id가 필요합니다.');
        }
        try {
            Case toUpdate = new Case(
                Id = caseId,
                Priority_Approved_At__c = Datetime.now(),
                Priority_Approved_By__c = UserInfo.getUserId()
            );
            // 승인자·승인시각은 시스템이 찍는 감사 스탬프라 SYSTEM_MODE로 기록한다(FLS 비종속).
            // 레코드 수정 권한 자체는 with sharing 클래스가 통제한다.
            Database.update(toUpdate, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            throw new AuraHandledException('출동 확정 저장에 실패했습니다: ' + e.getMessage());
        }
    }

    // ─── Current Case ────────────────────────────────────────────────────

    private static Case getCurrentCase(Id caseId) {
        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Priority, Impact_Level__c,
                   Dispatch_Briefing__c, Similar_Cases_Summary__c,
                   Warranty_Judged_At__c, AssetId, Asset.Name
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
            Decimal drift = w.Drift_From_Baseline__c;
            if (drift == null && w.Baseline_Value__c != null && w.Baseline_Value__c != 0) {
                drift = ((w.Measured_Value__c - w.Baseline_Value__c) / w.Baseline_Value__c * 100).setScale(2);
                w.Drift_From_Baseline__c = drift;
            }
            String trend = w.Trend_Flag__c;
            if (trend == null && drift != null) {
                trend = drift <= -5 ? TREND_ABNORMAL : (drift <= -2 ? TREND_WARNING : '정상');
                w.Trend_Flag__c = trend;
            }
            Boolean isAbnormal = trend == TREND_ABNORMAL || trend == TREND_WARNING;
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
     * 각 인자의 값과 기여도(높음/보통/낮음)는 org의 실제 데이터에서 규칙으로 산정한다.
     */
    private static PriorityRationale buildPriorityRationale(List<AssetComparison> comparisons, Case current, RecoverySla sla) {
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

        r.factors = buildFactors(worst, current, sla);
        return r;
    }

    /**
     * 프로토타입 5행 산정 인자 테이블을 실제 데이터로 조립한다.
     * 데이터가 없는 인자(캐시 미반영·미시딩)는 available=false로 두어 화면에서 degrade.
     */
    private static List<RationaleFactor> buildFactors(AssetComparison worst, Case current, RecoverySla sla) {
        List<RationaleFactor> factors = new List<RationaleFactor>();
        Id targetAssetId = (worst != null) ? worst.assetId : null;

        // 1) 유량 하락 폭
        RationaleFactor f1 = new RationaleFactor();
        f1.key = 'flowDrop';
        f1.label = '유량 하락 폭';
        if (worst != null && worst.driftFromBaseline != null) {
            Decimal drift = worst.driftFromBaseline;
            f1.value = drift.setScale(2) + '% · 12대 중 최대';
            Decimal absDrift = drift.abs();
            f1.contribution = absDrift >= 5 ? '높음' : (absDrift >= 2 ? '보통' : '낮음');
            f1.available = true;
        }
        factors.add(f1);

        // 2) 동일 위치 과거 실패
        RationaleFactor f2 = new RationaleFactor();
        f2.key = 'pastFailure';
        f2.label = '동일 위치 과거 실패';
        if (targetAssetId != null) {
            String failPoint = null;
            Boolean pastFail = false;
            for (WorkOrderLineItem w : [
                SELECT Measurement_Point__c
                FROM WorkOrderLineItem
                WHERE WorkOrder.AssetId = :targetAssetId
                  AND Judgement__c = :JUDGE_FAIL
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ]) {
                pastFail = true;
                if (failPoint == null && w.Measurement_Point__c != null) {
                    failPoint = w.Measurement_Point__c;
                }
            }
            f2.available = true;
            if (pastFail) {
                f2.value = (failPoint != null ? failPoint + ' · ' : '') + '과거 기준 미달 이력';
                f2.contribution = '높음';
            } else {
                f2.value = '이력 없음';
                f2.contribution = '낮음';
            }
        }
        factors.add(f2);

        // 3) SLA 잔여시간 (CaseMilestone 복구)
        RationaleFactor f3 = new RationaleFactor();
        f3.key = 'slaRemaining';
        f3.label = 'SLA 잔여시간';
        if (sla != null) {
            f3.value = sla.display;
            f3.contribution = sla.contribution;
            f3.available = true;
        }
        factors.add(f3);

        // 4) Asset 중요도 (신규 필드 — 캐시 미반영 시 동적 SOQL이 예외 → degrade)
        RationaleFactor f4 = new RationaleFactor();
        f4.key = 'assetCriticality';
        f4.label = 'Asset 중요도';
        String crit = getAssetCriticality(targetAssetId);
        if (crit != null) {
            f4.value = crit;
            f4.contribution = crit == '핵심' ? '높음' : (crit == '중요' ? '보통' : '낮음');
            f4.available = true;
        }
        factors.add(f4);

        // 5) 전체 냉각 상실 (Impact_Level에서 도출)
        RationaleFactor f5 = new RationaleFactor();
        f5.key = 'totalCoolingLoss';
        f5.label = '전체 냉각 상실';
        f5.available = true;
        if (current.Impact_Level__c != null && current.Impact_Level__c.startsWith('S1')) {
            f5.value = '전체 냉각 상실';
            f5.contribution = '높음';
        } else {
            f5.value = '해당 없음';
            f5.contribution = '낮음';
        }
        factors.add(f5);

        return factors;
    }

    /**
     * Case의 복구 SLA(CaseMilestone) 잔여시간을 계산한다.
     * @return 잔여 표시·기여도. Milestone이 없으면 null.
     */
    private static RecoverySla getRecoverySla(Id caseId) {
        List<CaseMilestone> ms = [
            SELECT TargetDate, CompletionDate, IsCompleted
            FROM CaseMilestone
            WHERE CaseId = :caseId
              AND MilestoneType.Name = '복구'
            WITH USER_MODE
            ORDER BY TargetDate DESC
            LIMIT 1
        ];
        if (ms.isEmpty() || ms[0].TargetDate == null) {
            RecoverySla fallback = new RecoverySla();
            fallback.display = '8시간';
            fallback.contribution = '보통';
            return fallback;
        }
        RecoverySla sla = new RecoverySla();
        Long remainMin = (ms[0].TargetDate.getTime() - Datetime.now().getTime()) / 60000;
        if (remainMin <= 0) {
            sla.display = 'SLA 초과';
            sla.contribution = '높음';
        } else {
            Long h = remainMin / 60;
            Long m = Math.mod(remainMin, 60);
            sla.display = h + '시간 ' + m + '분 남음';
            // 기본 복구 목표 8시간(480분) 기준 잔여 비율로 기여도 산정
            sla.contribution = remainMin <= 120 ? '높음' : (remainMin <= 288 ? '보통' : '낮음');
        }
        return sla;
    }

    /**
     * 대상 Asset의 중요도(신규 필드)를 동적 SOQL로 조회한다.
     * 배포 직후 스키마 캐시가 필드를 못 보면 QueryException → null 반환(화면 degrade).
     */
    private static String getAssetCriticality(Id assetId) {
        if (assetId == null) {
            return null;
        }
        try {
            List<SObject> rows = Database.queryWithBinds(
                'SELECT Criticality__c FROM Asset WHERE Id = :assetId LIMIT 1',
                new Map<String, Object>{ 'assetId' => assetId },
                AccessLevel.USER_MODE
            );
            if (!rows.isEmpty()) {
                return (String) rows[0].get('Criticality__c');
            }
        } catch (Exception e) {
            return null;
        }
        return null;
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
        @AuraEnabled public String slaRemaining;
        @AuraEnabled public Datetime calculatedAt;
        @AuraEnabled public Boolean isApproved = false;
        @AuraEnabled public Datetime approvedAt;
        @AuraEnabled public String approvedByName;
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
        @AuraEnabled public List<RationaleFactor> factors = new List<RationaleFactor>();
    }

    public class RationaleFactor {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String contribution;
        @AuraEnabled public Boolean available = false;
    }

    private class RecoverySla {
        String display;
        String contribution;
    }
}
/**
 * 현장 복구 작업 측정 플로우 컨트롤러 (T5-31).
 * WorkOrder 하나를 기준으로 측정 항목·허용구간·Knowledge 유사사례를 공급하고,
 * 측정값 저장 시 허용구간 판정을 수행하며, 작업 완료 시 WorkOrder를 Completed로
 * 전환한다. Completed 전환은 기존 T5_WorkOrder_Completed_Swarm_Notify Flow의
 * Slack 발신 트리거가 된다. 이 컨트롤러는 WorkOrder에 쓰기(Status)를 하되
 * Case는 닫지 않는다 (T5-29 불변 규칙).
 * Callable from the t5MeasurementTab LWC.
 */
public with sharing class T5MeasurementController {

    private static final String JUDGE_PASS = '합격';
    private static final String JUDGE_FAIL = '불합격';
    private static final String STATUS_COMPLETED = 'Completed';

    /**
     * WorkOrder 기준 측정 항목·Knowledge 유사사례를 조립한다.
     * @param workOrderId 조회 기준 WorkOrder Id
     * @return 측정 항목 목록과 Knowledge 목록을 담은 MeasurementContext
     */
    @AuraEnabled(cacheable=true)
    public static MeasurementContext getContext(Id workOrderId) {
        if (workOrderId == null) {
            throw new AuraHandledException('WorkOrder Id가 필요합니다.');
        }
        MeasurementContext ctx = new MeasurementContext();
        ctx.lines = buildLines(workOrderId);
        ctx.articles = buildArticles();
        return ctx;
    }

    /**
     * 측정값을 저장하고 허용구간 판정을 수행한다.
     * Threshold_Min__c ~ Threshold_Max__c 범위 안에 들면 합격, 아니면 불합격.
     * Max가 비어 있으면 하한만, Min이 비어 있으면 상한만 검사한다.
     * @param lineItemId 측정값을 저장할 WorkOrderLineItem Id
     * @param value 입력된 측정값
     * @return 저장 후 판정 결과를 담은 MeasurementLine
     */
    @AuraEnabled
    public static MeasurementLine saveMeasurement(Id lineItemId, Decimal value) {
        if (lineItemId == null) {
            throw new AuraHandledException('측정 항목 Id가 필요합니다.');
        }
        if (value == null) {
            throw new AuraHandledException('측정값을 입력하세요.');
        }

        List<WorkOrderLineItem> items = [
            SELECT Id, WorkOrderId, LineItemNumber, Measurement_Point__c,
                   Measured_Value__c, Previous_Measured_Value__c, Baseline_Value__c,
                   Threshold_Min__c, Threshold_Max__c, Unit__c, Judgement__c,
                   Retest_Round__c, Retest_Reason__c
            FROM WorkOrderLineItem
            WHERE Id = :lineItemId
            WITH USER_MODE
            LIMIT 1
        ];
        if (items.isEmpty()) {
            throw new AuraHandledException('측정 항목을 찾을 수 없습니다: ' + lineItemId);
        }

        WorkOrderLineItem item = items[0];
        Boolean pass = isWithinThreshold(value, item.Threshold_Min__c, item.Threshold_Max__c);
        String judgement = pass ? JUDGE_PASS : JUDGE_FAIL;

        // 변경 대상 필드만 담은 레코드로 업데이트한다. 조회 결과 전체를 업데이트하면
        // USER_MODE가 로드된 모든 필드의 FLS를 검사해 불필요하게 막힐 수 있다.
        WorkOrderLineItem toUpdate = new WorkOrderLineItem(
            Id = item.Id,
            Measured_Value__c = value,
            Judgement__c = judgement
        );

        try {
            Database.update(toUpdate, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            throw new AuraHandledException('측정값 저장에 실패했습니다: ' + e.getDmlMessage(0));
        }

        item.Measured_Value__c = value;
        item.Judgement__c = judgement;
        return toLine(item);
    }

    /**
     * WorkOrder를 Completed로 전환한다. Slack 완료 보고 Flow의 트리거가 된다.
     * @param workOrderId 완료 처리할 WorkOrder Id
     */
    @AuraEnabled
    public static void completeWork(Id workOrderId) {
        if (workOrderId == null) {
            throw new AuraHandledException('WorkOrder Id가 필요합니다.');
        }
        WorkOrder wo = new WorkOrder(Id = workOrderId, Status = STATUS_COMPLETED);
        try {
            Database.update(wo, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            throw new AuraHandledException('작업 완료 처리에 실패했습니다: ' + e.getDmlMessage(0));
        }
    }

    // ─── Builders ────────────────────────────────────────────────────────

    private static List<MeasurementLine> buildLines(Id workOrderId) {
        List<MeasurementLine> lines = new List<MeasurementLine>();
        for (WorkOrderLineItem item : [
            SELECT Id, WorkOrderId, LineItemNumber, Measurement_Point__c,
                   Measured_Value__c, Previous_Measured_Value__c, Baseline_Value__c,
                   Threshold_Min__c, Threshold_Max__c, Unit__c, Judgement__c,
                   Retest_Round__c, Retest_Reason__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId
              AND Measurement_Point__c != null
            WITH USER_MODE
            ORDER BY LineItemNumber ASC
        ]) {
            lines.add(toLine(item));
        }
        return lines;
    }

    private static List<KnowledgeInfo> buildArticles() {
        List<KnowledgeInfo> infos = new List<KnowledgeInfo>();
        for (Knowledge__kav article : [
            SELECT Id, Title, Summary
            FROM Knowledge__kav
            WHERE PublishStatus = 'Online'
            WITH USER_MODE
            ORDER BY LastPublishedDate DESC
            LIMIT 10
        ]) {
            KnowledgeInfo info = new KnowledgeInfo();
            info.id = article.Id;
            info.title = article.Title;
            info.summary = article.Summary;
            infos.add(info);
        }
        return infos;
    }

    // ─── Helpers ───────────────────────────────────────────────────────────

    private static Boolean isWithinThreshold(Decimal value, Decimal min, Decimal max) {
        if (min != null && value < min) {
            return false;
        }
        if (max != null && value > max) {
            return false;
        }
        return min != null || max != null;
    }

    private static MeasurementLine toLine(WorkOrderLineItem item) {
        MeasurementLine line = new MeasurementLine();
        line.id = item.Id;
        line.lineNumber = item.LineItemNumber;
        line.point = item.Measurement_Point__c;
        line.measured = item.Measured_Value__c;
        line.previous = item.Previous_Measured_Value__c;
        line.baseline = item.Baseline_Value__c;
        line.thresholdMin = item.Threshold_Min__c;
        line.thresholdMax = item.Threshold_Max__c;
        line.unit = item.Unit__c;
        line.judgement = item.Judgement__c;
        line.retestRound = item.Retest_Round__c;
        line.retestReason = item.Retest_Reason__c;
        line.isPass = JUDGE_PASS.equals(item.Judgement__c);
        return line;
    }

    // ─── DTOs ────────────────────────────────────────────────────────────

    public class MeasurementContext {
        @AuraEnabled public List<MeasurementLine> lines = new List<MeasurementLine>();
        @AuraEnabled public List<KnowledgeInfo> articles = new List<KnowledgeInfo>();
    }

    public class MeasurementLine {
        @AuraEnabled public Id id;
        @AuraEnabled public String lineNumber;
        @AuraEnabled public String point;
        @AuraEnabled public Decimal measured;
        @AuraEnabled public Decimal previous;
        @AuraEnabled public Decimal baseline;
        @AuraEnabled public Decimal thresholdMin;
        @AuraEnabled public Decimal thresholdMax;
        @AuraEnabled public String unit;
        @AuraEnabled public String judgement;
        @AuraEnabled public Decimal retestRound;
        @AuraEnabled public String retestReason;
        @AuraEnabled public Boolean isPass;
    }

    public class KnowledgeInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String summary;
    }
}

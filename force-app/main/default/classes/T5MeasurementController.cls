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
     * 측정값을 저장한다. 판정(Judgement__c)은 이 컨트롤러가 아니라 org의 기존
     * 자동화 Flow(WOLI_Judgement_AutoSet, RecordBeforeSave)가 수행한다. 그 Flow는
     * WorkOrder의 Technical_Baseline__c와 WOLI의 Measurement_Item_Code__c로
     * Technical_Baseline_Spec__c를 조회해 허용구간을 판정한다. 따라서 여기서는
     * Measured_Value__c만 쓰고, 저장 후 Flow가 세팅한 판정을 되읽어 반환한다.
     * 자체 판정을 쓰면 같은 트랜잭션의 BeforeSave Flow가 덮어써 무력해지기 때문.
     * @param lineItemId 측정값을 저장할 WorkOrderLineItem Id
     * @param value 입력된 측정값
     * @return 저장 후 Flow가 판정한 결과를 담은 MeasurementLine
     */
    @AuraEnabled
    public static MeasurementLine saveMeasurement(Id lineItemId, Decimal value) {
        if (lineItemId == null) {
            throw new AuraHandledException('측정 항목 Id가 필요합니다.');
        }
        if (value == null) {
            throw new AuraHandledException('측정값을 입력하세요.');
        }

        // 변경 대상 필드만 담은 레코드로 업데이트한다. 조회 결과 전체를 업데이트하면
        // USER_MODE가 로드된 모든 필드의 FLS를 검사해 불필요하게 막힐 수 있다.
        WorkOrderLineItem toUpdate = new WorkOrderLineItem(
            Id = lineItemId,
            Measured_Value__c = value
        );
        try {
            Database.update(toUpdate, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            throw new AuraHandledException('측정값 저장에 실패했습니다: ' + e.getDmlMessage(0));
        }

        // BeforeSave Flow가 판정을 세팅한 뒤 상태를 되읽는다.
        List<WorkOrderLineItem> items = [
            SELECT Id, WorkOrderId, LineItemNumber, Measurement_Point__c,
                   Measurement_Item_Code__c,
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
        return toLine(items[0]);
    }

    /**
     * 같은 자산·같은 측정 항목 코드의 과거 측정 이력을 최근순으로 반환한다.
     * 현재 WO 자신의 WOLI는 제외한다. UI의 "이력 보기" 토글에서 사용.
     */
    @AuraEnabled(cacheable=true)
    public static List<HistoryEntry> getHistory(Id workOrderId, String itemCode, Integer maxRows) {
        if (workOrderId == null || String.isBlank(itemCode)) {
            return new List<HistoryEntry>();
        }
        Integer lim = (maxRows == null || maxRows <= 0) ? 5 : maxRows;
        List<WorkOrder> owner = [
            SELECT Id, AssetId FROM WorkOrder WHERE Id = :workOrderId WITH USER_MODE LIMIT 1
        ];
        if (owner.isEmpty() || owner[0].AssetId == null) {
            return new List<HistoryEntry>();
        }
        Id assetId = owner[0].AssetId;
        List<HistoryEntry> out = new List<HistoryEntry>();
        for (WorkOrderLineItem item : [
            SELECT Id, WorkOrderId, WorkOrder.WorkOrderNumber, WorkOrder.CreatedDate,
                   Measured_Value__c, Unit__c, Judgement__c, Retest_Round__c
            FROM WorkOrderLineItem
            WHERE WorkOrder.AssetId = :assetId
              AND Measurement_Item_Code__c = :itemCode
              AND WorkOrderId != :workOrderId
              AND Measured_Value__c != null
              AND Measurement_Point__c != null
              AND Unit__c != null
            WITH USER_MODE
            ORDER BY WorkOrder.CreatedDate DESC
            LIMIT :lim
        ]) {
            HistoryEntry e = new HistoryEntry();
            e.id = item.Id;
            e.workOrderNumber = item.WorkOrder.WorkOrderNumber;
            e.measuredAt = item.WorkOrder.CreatedDate;
            e.measured = item.Measured_Value__c;
            e.unit = item.Unit__c;
            e.judgement = item.Judgement__c;
            e.isPass = JUDGE_PASS.equals(item.Judgement__c);
            e.retestRound = item.Retest_Round__c;
            out.add(e);
        }
        return out;
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

        // SA도 함께 Completed 로 바꿔 FSM 모바일 앱 status 반영.
        // SA가 없으면 스킵. USER_MODE로 접근권한 검사.
        List<ServiceAppointment> sas = [
            SELECT Id, Status FROM ServiceAppointment
            WHERE ParentRecordId = :workOrderId
              AND Status != :STATUS_COMPLETED
            WITH USER_MODE
        ];
        if (!sas.isEmpty()) {
            List<ServiceAppointment> toUpdate = new List<ServiceAppointment>();
            for (ServiceAppointment sa : sas) {
                toUpdate.add(new ServiceAppointment(Id = sa.Id, Status = STATUS_COMPLETED));
            }
            try {
                Database.update(toUpdate, AccessLevel.USER_MODE);
            } catch (DmlException e) {
                // SA 실패는 blocker 아님 - WO는 이미 Completed. 로그만 남기고 통과.
                System.debug(LoggingLevel.WARN, 'SA Completed 반영 실패: ' + e.getDmlMessage(0));
            }
        }
    }

    // ─── Builders ────────────────────────────────────────────────────────

    private static List<MeasurementLine> buildLines(Id workOrderId) {
        List<MeasurementLine> lines = new List<MeasurementLine>();
        for (WorkOrderLineItem item : [
            SELECT Id, WorkOrderId, LineItemNumber, Measurement_Point__c,
                   Measurement_Item_Code__c,
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

    private static MeasurementLine toLine(WorkOrderLineItem item) {
        MeasurementLine line = new MeasurementLine();
        line.id = item.Id;
        line.lineNumber = item.LineItemNumber;
        line.point = item.Measurement_Point__c;
        line.itemCode = item.Measurement_Item_Code__c;
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
        @AuraEnabled public String itemCode;
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

    public class HistoryEntry {
        @AuraEnabled public Id id;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public Datetime measuredAt;
        @AuraEnabled public Decimal measured;
        @AuraEnabled public String unit;
        @AuraEnabled public String judgement;
        @AuraEnabled public Boolean isPass;
        @AuraEnabled public Decimal retestRound;
    }

    public class KnowledgeInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String summary;
    }
}
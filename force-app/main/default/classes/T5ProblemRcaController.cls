/**
 * Problem/RCA 검토 화면 데이터 공급 컨트롤러 (S-04, step18 v-rca).
 * Case Id를 받아 연결된 Problem의 원인 구분(직접 원인·조직 차원 근본원인)과
 * 영향 범위(시정조치 1건·예방확인 N건 집계)를 하나의 DTO로 묶어 반환한다.
 * "AI가 원인을 확정"이 아니라 "규칙·집계가 후보를 준비하고 담당자가 승인"하는
 * 데모 메시지를 화면에 담는다. Callable from the otProblemRca LWC via @wire.
 */
public with sharing class T5ProblemRcaController {

    private static final String SUBTYPE_CORRECTIVE = '시정조치';
    private static final String SUBTYPE_PREVENTIVE = '예방정비';
    private static final String SUBTYPE_COMMISSION = '시운전';
    private static final String SUBTYPE_RECOVERY = '장애복구';
    private static final String ITEM_TORQUE = '체결토크';
    private static final String JUDGE_FAIL = '불합격';
    private static final String JUDGE_PASS = '합격';

    /**
     * 현재 Case 기준으로 Problem/RCA 검토 데이터를 조립한다.
     * @param caseId 조회 기준 Case Id
     * @return Problem 원인 구분·영향 범위 집계를 담은 ProblemRca
     * @throws AuraHandledException Case/Problem을 찾을 수 없을 때
     */
    @AuraEnabled(cacheable=true)
    public static ProblemRca getRca(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id가 필요합니다.');
        }
        Case current = getCurrentCase(caseId);
        if (current.Problem__c == null) {
            throw new AuraHandledException('Case에 연결된 Problem이 없습니다.');
        }

        Problem prob = getProblem(current.Problem__c);

        ProblemRca result = new ProblemRca();
        result.caseNumber = current.CaseNumber;
        result.problemNumber = prob.ProblemNumber;
        result.subject = prob.Subject;
        result.directCause = prob.RootCauseSummary;
        result.rootCause = prob.Description;
        result.workaround = prob.Workaround;

        applyScopeCounts(result, prob.Id);
        result.evidence = buildArticleEvidence(current.AssetId, current.CaseNumber, prob.ProblemNumber);
        return result;
    }

    /**
     * 영향 범위 승인 후 조치 생성 결과(step19 v-actions)를 조립한다.
     * 시정/예방 집계·합계, 생성된 Work Order 목록, 신규사례 Article 초안 근거값을
     * 실데이터로 채운다. 점검표 Rev.2→Rev.3와 신규감지 문구는 시나리오 기반 정적이라
     * 화면(LWC)에서 처리한다.
     * @param caseId 조회 기준 Case Id
     * @return 조치 결과·WO 목록·Article 근거를 담은 ActionResults
     * @throws AuraHandledException Case/Problem을 찾을 수 없을 때
     */
    @AuraEnabled(cacheable=true)
    public static ActionResults getActions(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id가 필요합니다.');
        }
        Case current = getCurrentCase(caseId);
        if (current.Problem__c == null) {
            throw new AuraHandledException('Case에 연결된 Problem이 없습니다.');
        }
        Problem prob = getProblem(current.Problem__c);

        ActionResults result = new ActionResults();
        result.caseNumber = current.CaseNumber;
        result.problemNumber = prob.ProblemNumber;

        applyScopeCounts(result, prob.Id);
        result.workOrders = buildWorkOrderList(prob.Id);
        result.articleEvidence = buildArticleEvidence(current.AssetId, current.CaseNumber, prob.ProblemNumber);
        return result;
    }

    /**
     * Problem에 연결된 Work Order 목록을 서브타입 배지와 함께 조립한다.
     * 담당자·기한은 시딩되지 않아 제외하고 번호·제목·서브타입만 표시한다.
     */
    private static List<ActionWorkOrder> buildWorkOrderList(Id problemId) {
        List<ActionWorkOrder> rows = new List<ActionWorkOrder>();
        for (WorkOrder wo : [
            SELECT WorkOrderNumber, Subject, Work_Subtype__c
            FROM WorkOrder
            WHERE Problem__c = :problemId
            WITH USER_MODE
            ORDER BY WorkOrderNumber
        ]) {
            ActionWorkOrder r = new ActionWorkOrder();
            r.workOrderNumber = wo.WorkOrderNumber;
            r.subject = wo.Subject;
            r.subtype = wo.Work_Subtype__c;
            r.isCorrective = wo.Work_Subtype__c == SUBTYPE_CORRECTIVE;
            rows.add(r);
        }
        return rows;
    }

    /**
     * 신규사례 Article 초안의 근거 수치를 실데이터로 조립한다.
     * 2022 시운전(68→112)·2026 복구(71→111) F-07 체결토크 최초/재시험값.
     */
    private static ArticleEvidence buildArticleEvidence(Id assetId, String caseNumber, String problemNumber) {
        ArticleEvidence ev = new ArticleEvidence();
        ev.caseNumber = caseNumber;
        ev.problemNumber = problemNumber;
        if (assetId == null) {
            return ev;
        }
        for (WorkOrderLineItem w : [
            SELECT WorkOrder.Work_Subtype__c, Measured_Value__c, Judgement__c
            FROM WorkOrderLineItem
            WHERE WorkOrder.AssetId = :assetId
              AND Measurement_Item_Code__c = :ITEM_TORQUE
              AND Measurement_Point__c = 'F-07'
              AND WorkOrder.Work_Subtype__c IN (:SUBTYPE_COMMISSION, :SUBTYPE_RECOVERY)
            WITH USER_MODE
            ORDER BY Retest_Round__c ASC
        ]) {
            Boolean isCommission = w.WorkOrder.Work_Subtype__c == SUBTYPE_COMMISSION;
            if (w.Judgement__c == JUDGE_FAIL) {
                if (isCommission) {
                    ev.commissionFail = w.Measured_Value__c;
                } else {
                    ev.recoveryFail = w.Measured_Value__c;
                }
            } else if (w.Judgement__c == JUDGE_PASS) {
                if (isCommission) {
                    ev.commissionPass = w.Measured_Value__c;
                } else {
                    ev.recoveryPass = w.Measured_Value__c;
                }
            }
        }
        return ev;
    }

    // ─── Current Case ────────────────────────────────────────────────────

    private static Case getCurrentCase(Id caseId) {
        List<Case> cases = [
            SELECT Id, CaseNumber, AssetId, Problem__c
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

    // ─── Problem 원인 구분 ─────────────────────────────────────────────────

    private static Problem getProblem(Id problemId) {
        List<Problem> problems = [
            SELECT Id, ProblemNumber, Subject, RootCauseSummary, Description, Workaround
            FROM Problem
            WHERE Id = :problemId
            WITH USER_MODE
            LIMIT 1
        ];
        if (problems.isEmpty()) {
            throw new AuraHandledException('Problem을 찾을 수 없습니다: ' + problemId);
        }
        return problems[0];
    }

    // ─── 영향 범위 집계 (시정조치 1 / 예방확인 N) ────────────────────────────

    /**
     * Problem에 연결된 Work Order를 서브타입별로 집계해 시정·예방 건수를 채운다.
     * 시정조치 = A-07 직접 조치, 예방정비 = 나머지 장비 예방확인.
     * @param result 채울 대상 DTO
     * @param problemId 집계 기준 Problem Id
     */
    private static void applyScopeCounts(ProblemRca result, Id problemId) {
        ScopeCounts sc = countScope(problemId);
        result.correctiveCount = sc.corrective;
        result.preventiveCount = sc.preventive;
        result.totalCount = sc.corrective + sc.preventive;
    }

    private static void applyScopeCounts(ActionResults result, Id problemId) {
        ScopeCounts sc = countScope(problemId);
        result.correctiveCount = sc.corrective;
        result.preventiveCount = sc.preventive;
        result.totalCount = sc.corrective + sc.preventive;
    }

    /**
     * Problem에 연결된 Work Order를 서브타입별로 집계한다.
     * 시정조치 = A-07 직접 조치, 예방정비 = 나머지 장비 예방확인.
     */
    private static ScopeCounts countScope(Id problemId) {
        ScopeCounts sc = new ScopeCounts();
        for (AggregateResult ar : [
            SELECT Work_Subtype__c subtype, COUNT(Id) cnt
            FROM WorkOrder
            WHERE Problem__c = :problemId
            WITH USER_MODE
            GROUP BY Work_Subtype__c
        ]) {
            String subtype = (String) ar.get('subtype');
            Integer cnt = (Integer) ar.get('cnt');
            if (subtype == SUBTYPE_CORRECTIVE) {
                sc.corrective = cnt;
            } else if (subtype == SUBTYPE_PREVENTIVE) {
                sc.preventive = cnt;
            }
        }
        return sc;
    }

    private class ScopeCounts {
        Integer corrective = 0;
        Integer preventive = 0;
    }

    // ─── DTO ─────────────────────────────────────────────────────────────

    public class ProblemRca {
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String problemNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String directCause;
        @AuraEnabled public String rootCause;
        @AuraEnabled public String workaround;
        @AuraEnabled public Integer correctiveCount = 0;
        @AuraEnabled public Integer preventiveCount = 0;
        @AuraEnabled public Integer totalCount = 0;
        @AuraEnabled public ArticleEvidence evidence;
    }

    public class ActionResults {
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String problemNumber;
        @AuraEnabled public Integer correctiveCount = 0;
        @AuraEnabled public Integer preventiveCount = 0;
        @AuraEnabled public Integer totalCount = 0;
        @AuraEnabled public List<ActionWorkOrder> workOrders = new List<ActionWorkOrder>();
        @AuraEnabled public ArticleEvidence articleEvidence;
    }

    public class ActionWorkOrder {
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String subtype;
        @AuraEnabled public Boolean isCorrective = false;
    }

    public class ArticleEvidence {
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String problemNumber;
        @AuraEnabled public Decimal commissionFail;
        @AuraEnabled public Decimal commissionPass;
        @AuraEnabled public Decimal recoveryFail;
        @AuraEnabled public Decimal recoveryPass;
    }
}
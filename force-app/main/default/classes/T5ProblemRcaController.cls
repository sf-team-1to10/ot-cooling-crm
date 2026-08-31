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
        return result;
    }

    // ─── Current Case ────────────────────────────────────────────────────

    private static Case getCurrentCase(Id caseId) {
        List<Case> cases = [
            SELECT Id, CaseNumber, Problem__c
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
                result.correctiveCount = cnt;
            } else if (subtype == SUBTYPE_PREVENTIVE) {
                result.preventiveCount = cnt;
            }
        }
        result.totalCount = result.correctiveCount + result.preventiveCount;
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
    }
}

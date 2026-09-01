/**
 * Invocable Apex action for T5-20 유사 사례 검색.
 * 현재 Case와 같은 장비 모델(Asset.Product2Id)·같은 증상(Symptom_Category__c)으로
 * 접수된 과거 종결 Case를 검색해, Similar_Case_Search 프롬프트가 소비할 수 있는
 * 파이프 구분 목록 문자열로 반환한다.
 * Callable from Flows and Agentforce.
 */
public with sharing class OTSimilarCaseSearch {

    private static final String LINE_SEPARATOR = '\n';
    private static final String FIELD_SEPARATOR = ' | ';

    // ─── Invocable Method ────────────────────────────────────────────────

    /**
     * 현재 Case별로 같은 모델·같은 증상 과거 종결 Case 목록 문자열을 만든다.
     * @param requests 호출 Flow가 넘긴 현재 Case Id 목록
     * @return 각 요청에 대응하는 유사 사례 목록 문자열 응답
     */
    @InvocableMethod(
        label='유사 사례 검색'
        description='현재 Case와 같은 장비 모델·같은 증상의 과거 종결 Case를 검색해 파이프 구분 목록으로 반환한다'
        category='T5 Dispatch Briefing'
    )
    public static List<Response> search(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        Set<Id> caseIds = new Set<Id>();
        for (Request req : requests) {
            if (req.caseId != null) {
                caseIds.add(req.caseId);
            }
        }

        Map<Id, Case> currentCaseById = caseIds.isEmpty()
            ? new Map<Id, Case>()
            : new Map<Id, Case>([
                SELECT Id, Symptom_Category__c, Asset.Product2Id
                FROM Case
                WHERE Id IN :caseIds
                WITH USER_MODE
            ]);

        for (Request req : requests) {
            responses.add(buildResponse(req, currentCaseById.get(req.caseId)));
        }

        return responses;
    }

    // ─── Private Helpers ─────────────────────────────────────────────────

    /**
     * 단일 요청을 처리해 유사 사례 목록 문자열 응답을 만든다.
     * 오류는 던지지 않고 응답에 담는다.
     * @param req 입력 요청
     * @param currentCase 현재 Case (모델·증상 기준값)
     * @return 유사 사례 목록과 성공/오류 정보를 담은 Response
     */
    private static Response buildResponse(Request req, Case currentCase) {
        Response res = new Response();
        res.similarCases = '';

        try {
            if (currentCase == null) {
                res.isSuccess = false;
                res.errorMessage = 'Case not found: ' + req.caseId;
                res.errorType = 'NOT_FOUND';
                return res;
            }

            Id productId = currentCase.Asset?.Product2Id;
            String symptom = currentCase.Symptom_Category__c;

            // 모델·증상 기준값이 없으면 검색 불가 — 빈 목록으로 정상 반환(회귀 안전)
            if (productId == null || String.isBlank(symptom)) {
                res.isSuccess = true;
                return res;
            }

            List<Case> similar = [
                SELECT CaseNumber, CreatedDate, ClosedDate,
                       Symptom_Category__c, Diagnosed_Cause__c, Resolution_Hours__c
                FROM Case
                WHERE Asset.Product2Id = :productId
                  AND Symptom_Category__c = :symptom
                  AND Status = 'Closed'
                  AND Id != :currentCase.Id
                WITH USER_MODE
                ORDER BY ClosedDate DESC
            ];

            res.similarCases = formatCases(similar);
            res.isSuccess = true;
        } catch (Exception e) {
            res.isSuccess = false;
            res.errorMessage = e.getMessage();
            res.errorType = e.getTypeName();
        }

        return res;
    }

    /**
     * 종결 Case 목록을 프롬프트가 기대하는 파이프 구분 목록으로 조립한다.
     * 형식: Case번호 | 접수일 | 종료일 | 증상분류 | 진단원인 | 복구시간(시간)
     * @param cases 종결 Case 목록
     * @return 줄바꿈으로 구분된 목록 문자열 (없으면 빈 문자열)
     */
    private static String formatCases(List<Case> cases) {
        if (cases == null || cases.isEmpty()) {
            return '';
        }

        List<String> lines = new List<String>();
        for (Case c : cases) {
            List<String> parts = new List<String>{
                emptyIfNull(c.CaseNumber),
                formatDate(c.CreatedDate),
                formatDate(c.ClosedDate),
                emptyIfNull(c.Symptom_Category__c),
                emptyIfNull(c.Diagnosed_Cause__c),
                recoveryHours(c)
            };
            lines.add(String.join(parts, FIELD_SEPARATOR));
        }
        return String.join(lines, LINE_SEPARATOR);
    }

    /**
     * 복구시간(시간)을 반환한다. 명시 저장된 Resolution_Hours__c를 우선 인용하고,
     * 없으면 ClosedDate−CreatedDate로 산정한다(둘 다 없으면 빈 문자열).
     * 감사필드는 과거 시점으로 백데이트할 수 없어, 시딩 데이터는 명시 필드를 쓴다.
     * @param c 대상 종결 Case
     * @return 복구시간 문자열; 계산 불가 시 빈 문자열
     */
    private static String recoveryHours(Case c) {
        if (c.Resolution_Hours__c != null) {
            return c.Resolution_Hours__c.setScale(1).toPlainString();
        }
        if (c.CreatedDate == null || c.ClosedDate == null) {
            return '';
        }
        Decimal hours = (c.ClosedDate.getTime() - c.CreatedDate.getTime()) / (1000.0 * 60 * 60);
        return hours.setScale(1).toPlainString();
    }

    /**
     * Datetime을 yyyy-MM-dd 문자열로 변환한다.
     * @param value 대상 일시
     * @return 날짜 문자열; null이면 빈 문자열
     */
    private static String formatDate(Datetime value) {
        return value == null ? '' : value.format('yyyy-MM-dd');
    }

    /**
     * null을 빈 문자열로 치환한다.
     * @param value 대상 문자열
     * @return 원본 또는 빈 문자열
     */
    private static String emptyIfNull(String value) {
        return value == null ? '' : value;
    }

    // ─── Request / Response DTOs ─────────────────────────────────────────

    /**
     * 호출 Flow의 입력 파라미터
     */
    public class Request {
        @InvocableVariable(label='Case Id' description='유사 사례를 검색할 기준 Case의 Id' required=true)
        public Id caseId;
    }

    /**
     * 호출 Flow로 반환하는 출력
     */
    public class Response {
        @InvocableVariable(label='Similar Cases' description='같은 모델·같은 증상 과거 종결 Case의 파이프 구분 목록')
        public String similarCases;

        @InvocableVariable(label='Success' description='액션 성공 여부')
        public Boolean isSuccess;

        @InvocableVariable(label='Error Message' description='실패 시 오류 상세')
        public String errorMessage;

        @InvocableVariable(label='Error Type' description='실패 시 예외 타입명')
        public String errorType;
    }
}

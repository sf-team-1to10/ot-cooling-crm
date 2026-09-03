/**
 * MessagingSession 레코드 페이지의 케이스 워크 패널에 필요한
 * CaseId와 케이스 헤더 데이터를 공급한다.
 */
public inherited sharing class OtMsCaseWorkController {

    /**
     * MessagingSession → CaseId 조회.
     * @param sessionId MessagingSession Id
     * @return CaseId (없으면 null)
     */
    @AuraEnabled(cacheable=true)
    public static Id getCaseId(Id sessionId) {
        if (sessionId == null) {
            throw new AuraHandledException('sessionId는 필수입니다.');
        }
        try {
            List<MessagingSession> rows = [
                SELECT CaseId
                FROM   MessagingSession
                WHERE  Id = :sessionId
                LIMIT  1
            ];
            return rows.isEmpty() ? null : rows[0].CaseId;
        } catch (Exception e) {
            throw new AuraHandledException('세션 조회 오류: ' + e.getMessage());
        }
    }
}

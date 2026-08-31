/**
 * Case 360 상단 헤더 하이라이트 데이터 공급 컨트롤러 (S-01).
 * Case Id를 받아 프로토타입 4번 장면의 헤더 스트립 — Case번호·Asset·Agent 최초응답·
 * 상담사 인수·응답 SLA·복구 SLA — 을 하나의 DTO로 묶어 반환한다.
 * Agent 시각 2필드는 org 스키마 캐시가 미반영일 수 있어 동적 SOQL + degrade로 처리한다.
 */
public with sharing class T5CaseHeaderController {

    /**
     * Case 헤더 하이라이트 데이터를 조립한다.
     * @param caseId 조회 기준 Case Id
     * @return 6개 헤더 스탯과 타이틀·상태를 담은 CaseHeader
     */
    @AuraEnabled(cacheable=true)
    public static CaseHeader getHeader(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id가 필요합니다.');
        }

        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Status, Symptom_Category__c,
                   Account.Name, Asset.Name
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            throw new AuraHandledException('Case를 찾을 수 없습니다: ' + caseId);
        }
        Case current = cases[0];

        CaseHeader h = new CaseHeader();
        h.caseId = current.Id;
        h.caseNumber = current.CaseNumber;
        h.subject = current.Subject;
        h.symptomCategory = current.Symptom_Category__c;
        h.status = current.Status;
        h.accountName = current.Account?.Name;
        h.assetName = current.Asset?.Name;

        // Agent 시각 2필드 — 캐시 미반영 시 QueryException → null(degrade)
        Map<String, Datetime> times = getAgentTimes(current.Id);
        h.agentFirstResponseAt = times.get('first');
        h.agentHandoffAt = times.get('handoff');

        // 응답·복구 SLA — CaseMilestone duration(분)에서 도출
        Map<String, String> sla = getSlaTargets(current.Id);
        h.responseSla = sla.get('응답');
        h.recoverySla = sla.get('복구');

        return h;
    }

    /**
     * Agent 최초응답·상담사 인수 시각을 동적 SOQL로 조회한다.
     * 배포 직후 스키마 캐시가 필드를 못 보면 QueryException → 빈 맵(화면 degrade).
     */
    private static Map<String, Datetime> getAgentTimes(Id caseId) {
        Map<String, Datetime> result = new Map<String, Datetime>();
        try {
            List<SObject> rows = Database.queryWithBinds(
                'SELECT Agent_First_Response_At__c, Agent_Handoff_At__c ' +
                'FROM Case WHERE Id = :caseId LIMIT 1',
                new Map<String, Object>{ 'caseId' => caseId },
                AccessLevel.USER_MODE
            );
            if (!rows.isEmpty()) {
                result.put('first', (Datetime) rows[0].get('Agent_First_Response_At__c'));
                result.put('handoff', (Datetime) rows[0].get('Agent_Handoff_At__c'));
            }
        } catch (Exception e) {
            // 캐시 미반영 — 시각 스탯은 화면에서 '준비중'으로 degrade
        }
        return result;
    }

    /**
     * Case의 응답·복구 Milestone duration을 "N분 / N시간" 표시 문자열로 환산한다.
     * @return MilestoneType 이름 → SLA 표시 문자열
     */
    private static Map<String, String> getSlaTargets(Id caseId) {
        Map<String, String> result = new Map<String, String>();
        for (CaseMilestone m : [
            SELECT MilestoneType.Name, TargetDate, StartDate
            FROM CaseMilestone
            WHERE CaseId = :caseId
              AND TargetDate != null
              AND StartDate != null
            WITH USER_MODE
        ]) {
            Long durMin = (m.TargetDate.getTime() - m.StartDate.getTime()) / 60000;
            result.put(m.MilestoneType.Name, formatDuration(durMin));
        }
        return result;
    }

    /**
     * 분 단위 duration을 사람이 읽는 SLA 문자열로 만든다(60분 미만은 '분', 이상은 '시간').
     */
    private static String formatDuration(Long minutes) {
        if (minutes < 60) {
            return minutes + '분';
        }
        Long hours = minutes / 60;
        Long rem = Math.mod(minutes, 60);
        return rem == 0 ? hours + '시간' : hours + '시간 ' + rem + '분';
    }

    public class CaseHeader {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String symptomCategory;
        @AuraEnabled public String status;
        @AuraEnabled public String accountName;
        @AuraEnabled public String assetName;
        @AuraEnabled public Datetime agentFirstResponseAt;
        @AuraEnabled public Datetime agentHandoffAt;
        @AuraEnabled public String responseSla;
        @AuraEnabled public String recoverySla;
    }
}

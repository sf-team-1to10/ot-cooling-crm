/**
 * 담당자 확정 화면(otDispatchCandidates)의 [확정] 버튼이 부르는 서버 로직.
 * 후보 라벨(DeveloperName) → CMDT 매핑 조회 → WorkOrder OwnerId 세팅 →
 * Case Stage 승격(1→2, 다운그레이드 방지) → 표준 Salesforce↔Slack 통합의
 * Init_Enhanced_Slack_Swarm Flow 실행으로 Swarm+채널을 만든다. 채널 생성 후
 * T5_Swarm_Created_Invite_And_Summary가 CollaborationUrl 채워짐을 트리거로
 * 초대·요약 발신을 이어받는다.
 */
public with sharing class T5DispatchAssignController {

    public class NotConfiguredException extends Exception {}

    @AuraEnabled
    public static AssignResult confirmAssignment(Id caseId, String candidateKey) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id가 필요합니다.');
        }
        if (String.isBlank(candidateKey)) {
            throw new AuraHandledException('후보 키가 필요합니다.');
        }

        String prefix = String.valueOf(caseId).substring(0, 3);
        if (prefix == '0WO') {
            List<WorkOrder> parentWos = [SELECT CaseId FROM WorkOrder WHERE Id = :caseId LIMIT 1];
            if (parentWos.isEmpty() || parentWos[0].CaseId == null) {
                throw new AuraHandledException('WorkOrder에 연결된 Case가 없습니다.');
            }
            caseId = parentWos[0].CaseId;
        } else if (prefix != '500') {
            throw new AuraHandledException('지원하지 않는 레코드 타입입니다: ' + prefix);
        }

        T5_Dispatch_Candidate_User__mdt cand = T5_Dispatch_Candidate_User__mdt.getInstance(candidateKey);
        if (cand == null || String.isBlank(cand.User_Id__c)) {
            throw new AuraHandledException('이 후보는 데모에서 실제 배정되지 않습니다. (임시 데이터)');
        }
        Id ownerId = (Id) cand.User_Id__c;

        try {
            List<WorkOrder> wos = [
                SELECT Id FROM WorkOrder
                WHERE CaseId = :caseId
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!wos.isEmpty()) {
                update new WorkOrder(Id = wos[0].Id, OwnerId = ownerId);
            }

            List<Case> cases = [
                SELECT Id, CaseNumber, Subject, Stage__c
                FROM Case
                WHERE Id = :caseId
                LIMIT 1
            ];
            if (cases.isEmpty()) {
                AuraHandledException ex = new AuraHandledException('Case를 찾을 수 없습니다. caseId=' + caseId);
                ex.setMessage('Case를 찾을 수 없습니다. caseId=' + caseId);
                throw ex;
            }
            Case c = cases[0];

            if (shouldPromoteStage(c.Stage__c)) {
                c.Stage__c = '2 담당자 배정';
                update c;
            }

            AssignResult r = new AssignResult();
            r.ownerId = ownerId;
            r.resolvedCaseId = c.Id;
            r.stagePromoted = c.Stage__c == '2 담당자 배정';
            r.caseNumber = c.CaseNumber;
            r.caseSubject = c.Subject;
            return r;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('배정 처리 중 오류: ' + e.getMessage());
        }
    }

    private static Boolean shouldPromoteStage(String currentStage) {
        if (String.isBlank(currentStage)) return true;
        String head = currentStage.trim().split('\\s+')[0];
        try {
            return Integer.valueOf(head) < 2;
        } catch (Exception ignored) {
            return false;
        }
    }

    public class AssignResult {
        @AuraEnabled public Id ownerId;
        @AuraEnabled public Id resolvedCaseId;
        @AuraEnabled public Boolean stagePromoted;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String caseSubject;
    }
}

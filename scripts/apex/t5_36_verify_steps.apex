// T5-36 각 단계 개별 검증. AuraHandledException은 anon 컨텍스트에서 throw 불가라
// 컨트롤러 직접 호출 대신 로직 개별 재현.

Id caseId = '500bm00002sqTvSAAU';

// 1) CMDT 매핑 확인
T5_Dispatch_Candidate_User__mdt cand = T5_Dispatch_Candidate_User__mdt.getInstance('Kang_Sikong');
System.debug('강시공 UserId: ' + cand.User_Id__c);
List<T5_Swarm_Fixed_Participant__mdt> fixed = T5_Swarm_Fixed_Participant__mdt.getAll().values();
for (T5_Swarm_Fixed_Participant__mdt f : fixed) {
    System.debug('고정 참여자: ' + f.DeveloperName + ' → ' + f.User_Id__c);
}

// 2) Case 리셋 + WO owner + Stage 승격
update new Case(Id = caseId, Stage__c = '1 진단·브리핑');
List<WorkOrder> wos = [SELECT Id, WorkOrderNumber FROM WorkOrder WHERE CaseId = :caseId ORDER BY CreatedDate DESC LIMIT 1];
if (!wos.isEmpty()) {
    update new WorkOrder(Id = wos[0].Id, OwnerId = (Id) cand.User_Id__c);
    System.debug('WO ' + wos[0].WorkOrderNumber + ' owner 세팅 완료');
}
update new Case(Id = caseId, Stage__c = '2 담당자 배정');
System.debug('Case Stage → 2 담당자 배정');

// 3) Swarm init flow 직접 호출
Case c = [SELECT CaseNumber, Subject FROM Case WHERE Id = :caseId];
Map<String, Object> inputs = new Map<String, Object>{
    'recordId' => (String) caseId,
    'swarmName' => c.CaseNumber,
    'swarmDescription' => c.Subject,
    'source' => 'Flow'
};
try {
    Flow.Interview i = Flow.Interview.createInterview('swarming__Init_Enhanced_Slack_Swarm', inputs);
    i.start();
    System.debug('Swarm init flow 실행 완료');
    Object url = i.getVariableValue('swarmCollaborationUrl');
    System.debug('swarmCollaborationUrl=' + url);
} catch (Exception e) {
    System.debug('Flow EXCEPTION: ' + e.getTypeName() + ' - ' + e.getMessage());
}

// 4) 결과 확인
Case after = [SELECT Stage__c FROM Case WHERE Id = :caseId];
System.debug('Case Stage after: ' + after.Stage__c);
List<Swarm> swarms = [SELECT Id, Name, Status, CollaborationUrl FROM Swarm WHERE RelatedRecordId = :caseId ORDER BY CreatedDate DESC];
System.debug('Swarm count: ' + swarms.size());
for (Swarm s : swarms) {
    System.debug('Swarm ' + s.Name + ' status=' + s.Status + ' url=' + s.CollaborationUrl);
}

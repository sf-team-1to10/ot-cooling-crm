// T5-36 검증: [강시공 확정] 시뮬레이션.
// 1) Case 상태 0 접수로 리셋
// 2) confirmAssignment 실행 → WO owner + Case Stage + Swarm/채널 생성 확인
// 3) 후속 Swarm invite flow는 AsyncAfterCommit이라 여기선 Swarm 존재만 확인

Id caseId = '500bm00002sqTvSAAU';
update new Case(Id = caseId, Stage__c = '1 진단·브리핑');
System.debug('Case Stage reset to 1');

try {
    T5DispatchAssignController.AssignResult r =
        T5DispatchAssignController.confirmAssignment(caseId, 'Kang_Sikong');
    System.debug('ownerId=' + r.ownerId);
    System.debug('stagePromoted=' + r.stagePromoted);
    System.debug('swarmCollaborationUrl=' + r.swarmCollaborationUrl);
} catch (Exception e) {
    System.debug('EXCEPTION: ' + e.getTypeName() + ' - ' + e.getMessage());
    System.debug('STACK: ' + e.getStackTraceString());
}

Case c = [SELECT Stage__c FROM Case WHERE Id = :caseId];
System.debug('Case Stage after: ' + c.Stage__c);

List<WorkOrder> wos = [SELECT Id, WorkOrderNumber, OwnerId FROM WorkOrder WHERE CaseId = :caseId ORDER BY CreatedDate DESC];
for (WorkOrder wo : wos) {
    System.debug('WO ' + wo.WorkOrderNumber + ' owner=' + wo.OwnerId);
}

List<Swarm> swarms = [SELECT Id, Name, CollaborationUrl, Status FROM Swarm WHERE RelatedRecordId = :caseId ORDER BY CreatedDate DESC];
System.debug('Swarm count for Case: ' + swarms.size());
for (Swarm s : swarms) {
    System.debug('Swarm ' + s.Name + ' status=' + s.Status + ' url=' + s.CollaborationUrl);
}

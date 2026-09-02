// Case Status를 New로 바꿔서 CaseMilestone 생성 트리거
Case c = [SELECT Id, Status FROM Case WHERE CaseNumber = '00001031' LIMIT 1];
c.Status = 'New';
update c;
System.debug('Case status set to New');

// Milestone 생성 확인 (비동기일 수 있음)
List<CaseMilestone> ms = [SELECT Id, MilestoneType.Name, TargetDate FROM CaseMilestone WHERE CaseId = :c.Id];
System.debug('Milestones created: ' + ms.size());
for (CaseMilestone m : ms) {
    System.debug(m.MilestoneType.Name + ' → ' + m.TargetDate);
}

// 다시 Working으로 복구
c.Status = 'Working';
update c;
System.debug('Case status restored to Working');

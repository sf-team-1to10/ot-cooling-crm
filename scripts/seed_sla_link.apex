// Entitlement에 SLA Process 연결 + Case에 Entitlement 연결

Entitlement ent = [SELECT Id, SlaProcessId FROM Entitlement WHERE Name = 'CDU-A-07 보증' LIMIT 1];
SlaProcess slp = [SELECT Id FROM SlaProcess WHERE Name = 's2 장애 sla' LIMIT 1];

ent.SlaProcessId = slp.Id;
update ent;
System.debug('Entitlement SLA process linked: ' + slp.Id);

Case c = [SELECT Id, EntitlementId FROM Case WHERE CaseNumber = '00001031' LIMIT 1];
c.EntitlementId = ent.Id;
update c;
System.debug('Case EntitlementId linked: ' + ent.Id);

System.debug('=== SLA LINK COMPLETE ===');

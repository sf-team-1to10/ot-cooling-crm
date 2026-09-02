Asset a = [SELECT Id, Warranty_Type__c FROM Asset WHERE Id = '02ibm000003uetzAAA'];
System.debug('BEFORE Asset Warranty_Type: ' + a.Warranty_Type__c);
a.Warranty_Type__c = '연장보증';
update a;

Asset a2 = [SELECT Warranty_Type__c FROM Asset WHERE Id = '02ibm000003uetzAAA'];
System.debug('AFTER Asset Warranty_Type: ' + a2.Warranty_Type__c);

Case c = [SELECT Id, Coverage_Type__c FROM Case WHERE CaseNumber = '00001465'];
System.debug('BEFORE Case Coverage_Type: ' + c.Coverage_Type__c);
c.Coverage_Type__c = '연장보증';
update c;

Case c2 = [SELECT Coverage_Type__c FROM Case WHERE CaseNumber = '00001465'];
System.debug('AFTER Case Coverage_Type: ' + c2.Coverage_Type__c);

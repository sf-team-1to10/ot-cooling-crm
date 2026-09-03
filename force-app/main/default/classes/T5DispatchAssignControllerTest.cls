@IsTest
private class T5DispatchAssignControllerTest {

    @IsTest
    static void confirmAssignment_promotesStageAndSetsOwner() {
        Account a = new Account(Name = 'T5-36 Test Account');
        insert a;
        Case c = new Case(Subject = 'T5-36 Test', AccountId = a.Id, Stage__c = '1 진단·브리핑');
        insert c;
        WorkOrder wo = new WorkOrder(CaseId = c.Id, AccountId = a.Id, Subject = 'WO', Status = 'New');
        insert wo;

        Test.startTest();
        T5DispatchAssignController.AssignResult r =
            T5DispatchAssignController.confirmAssignment(c.Id, 'Kang_Sikong');
        Test.stopTest();

        System.assertNotEquals(null, r.ownerId, 'ownerId 세팅');
        System.assertEquals(true, r.stagePromoted, 'Stage 승격 확인');

        Case reread = [SELECT Stage__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('2 담당자 배정', reread.Stage__c);

        WorkOrder woReread = [SELECT OwnerId FROM WorkOrder WHERE Id = :wo.Id];
        System.assertEquals(r.ownerId, woReread.OwnerId);
    }

    @IsTest
    static void confirmAssignment_rejectsUnknownCandidate() {
        Account a = new Account(Name = 'T5-36 T2');
        insert a;
        Case c = new Case(Subject = 'T5-36 T2', AccountId = a.Id, Stage__c = '1 진단·브리핑');
        insert c;

        Boolean threw = false;
        try {
            T5DispatchAssignController.confirmAssignment(c.Id, 'Bogus_Key');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, '알 수 없는 후보는 예외');
    }

    @IsTest
    static void confirmAssignment_rejectsBlankInputs() {
        Boolean threwOnCase = false;
        try {
            T5DispatchAssignController.confirmAssignment(null, 'Kang_Sikong');
        } catch (AuraHandledException e) {
            threwOnCase = true;
        }
        System.assertEquals(true, threwOnCase);

        Boolean threwOnKey = false;
        Account a = new Account(Name = 'T5-36 T3');
        insert a;
        Case c = new Case(Subject = 'T5-36 T3', AccountId = a.Id);
        insert c;
        try {
            T5DispatchAssignController.confirmAssignment(c.Id, '');
        } catch (AuraHandledException e) {
            threwOnKey = true;
        }
        System.assertEquals(true, threwOnKey);
    }

    @IsTest
    static void confirmAssignment_doesNotDowngradeStage() {
        Account a = new Account(Name = 'T5-36 T4');
        insert a;
        Case c = new Case(Subject = 'T5-36 T4', AccountId = a.Id, Stage__c = '4 수리·복구');
        insert c;

        Test.startTest();
        T5DispatchAssignController.AssignResult r =
            T5DispatchAssignController.confirmAssignment(c.Id, 'Kang_Sikong');
        Test.stopTest();

        Case reread = [SELECT Stage__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('4 수리·복구', reread.Stage__c, '이미 4면 다운그레이드 없음');
        System.assertEquals(false, r.stagePromoted);
    }
}

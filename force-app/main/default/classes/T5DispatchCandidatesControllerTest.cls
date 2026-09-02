@isTest
private class T5DispatchCandidatesControllerTest {

    @isTest
    static void shouldReturnHeader() {
        Account acct = new Account(Name = 'Test Account');
        insert acct;

        Asset ast = new Asset(Name = 'CDU-TEST', AccountId = acct.Id);
        insert ast;

        Case c = new Case(Subject = 'Test', AccountId = acct.Id, AssetId = ast.Id);
        insert c;

        Test.startTest();
        T5DispatchCandidatesController.CandidatesHeader h =
            T5DispatchCandidatesController.getHeader(c.Id);
        Test.stopTest();

        System.assertEquals('Test Account', h.accountName);
        System.assertEquals('CDU-TEST', h.assetName);
        System.assertNotEquals(null, h.caseNumber);
    }

    @isTest
    static void shouldThrowOnNull() {
        try {
            T5DispatchCandidatesController.getHeader(null);
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Case Id'));
        }
    }
}

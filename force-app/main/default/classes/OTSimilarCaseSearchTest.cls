/**
 * Tests for OTSimilarCaseSearch invocable action.
 * Covers: match found, self/open/other-model/other-symptom exclusion,
 * missing base values (regression-safe empty), and not-found.
 */
@isTest
private class OTSimilarCaseSearchTest {

    @TestSetup
    static void setupTestData() {
        Account account = TestDataFactory.createAccount('OT Test Co', true);
        Product2 modelA = TestDataFactory.createProduct('ColdFlow CDU-A', true);
        Product2 modelB = TestDataFactory.createProduct('ColdFlow CDU-B', true);

        Asset assetA = TestDataFactory.createAssetForProduct(account.Id, modelA.Id, 'CDU-A-01', true);
        Asset assetB = TestDataFactory.createAssetForProduct(account.Id, modelB.Id, 'CDU-B-01', true);

        // 현재(진행 중) Case — 검색 기준. 모델 A / 유량저하
        TestDataFactory.createCase(assetA.Id, '유량저하', 'New', null, true);
        // 매칭되어야 하는 과거 종결 Case — 같은 모델 A / 같은 증상 / 복구시간 48.0h
        TestDataFactory.createCase(assetA.Id, '유량저하', 'Closed', '펌프 임펠러 마모', 48.0, true);
        // 제외: 같은 모델·같은 증상이나 아직 진행 중
        TestDataFactory.createCase(assetA.Id, '유량저하', 'Working', null, true);
        // 제외: 같은 모델이나 다른 증상, 종결
        TestDataFactory.createCase(assetA.Id, '누수', 'Closed', '배관 균열', true);
        // 제외: 다른 모델(B), 같은 증상, 종결
        TestDataFactory.createCase(assetB.Id, '유량저하', 'Closed', '밸브 고착', true);
    }

    private static Id currentCaseId() {
        return [
            SELECT Id FROM Case WHERE Status = 'New' AND Symptom_Category__c = '유량저하' LIMIT 1
        ].Id;
    }

    @isTest
    static void shouldReturnMatchingClosedCase_WhenSameModelAndSymptom() {
        // Given
        Id caseId = currentCaseId();
        OTSimilarCaseSearch.Request req = new OTSimilarCaseSearch.Request();
        req.caseId = caseId;

        // When
        System.Test.startTest();
        List<OTSimilarCaseSearch.Response> responses =
            OTSimilarCaseSearch.search(new List<OTSimilarCaseSearch.Request>{ req });
        System.Test.stopTest();

        // Then
        Assert.areEqual(1, responses.size(), 'One response per request');
        OTSimilarCaseSearch.Response res = responses[0];
        Assert.isTrue(res.isSuccess, 'Search should succeed');
        Assert.isTrue(
            res.similarCases.contains('펌프 임펠러 마모'),
            'Matching closed same-model same-symptom case must be included'
        );
        Assert.areEqual(
            1,
            res.similarCases.split('\n').size(),
            'Only the one matching closed case should be listed (open/other-symptom/other-model excluded)'
        );
        Assert.isTrue(
            res.similarCases.contains(' | '),
            'Output must use the pipe field separator'
        );
        Assert.isTrue(
            res.similarCases.contains('48.0'),
            'Explicit Resolution_Hours__c value must be quoted as recovery time'
        );
    }

    @isTest
    static void shouldReturnEmpty_WhenNoAssetOnCase() {
        // Given — Case with no Asset (no model resolvable)
        Case noAssetCase = TestDataFactory.createCase(null, '유량저하', 'New', null, true);
        OTSimilarCaseSearch.Request req = new OTSimilarCaseSearch.Request();
        req.caseId = noAssetCase.Id;

        // When
        System.Test.startTest();
        List<OTSimilarCaseSearch.Response> responses =
            OTSimilarCaseSearch.search(new List<OTSimilarCaseSearch.Request>{ req });
        System.Test.stopTest();

        // Then — regression-safe: success with empty list, no error
        Assert.isTrue(responses[0].isSuccess, 'Missing model should not error');
        Assert.areEqual('', responses[0].similarCases, 'No base model → empty similar cases');
    }

    @isTest
    static void shouldReturnNotFound_WhenCaseIdMissing() {
        // Given — a Case Id that will be deleted so lookup misses
        Case temp = TestDataFactory.createCase(null, '소음', 'New', null, true);
        Id missingId = temp.Id;
        delete temp;

        OTSimilarCaseSearch.Request req = new OTSimilarCaseSearch.Request();
        req.caseId = missingId;

        // When
        System.Test.startTest();
        List<OTSimilarCaseSearch.Response> responses =
            OTSimilarCaseSearch.search(new List<OTSimilarCaseSearch.Request>{ req });
        System.Test.stopTest();

        // Then
        Assert.isFalse(responses[0].isSuccess, 'Deleted/missing Case should not succeed');
        Assert.areEqual('NOT_FOUND', responses[0].errorType, 'Error type should be NOT_FOUND');
    }

    @isTest
    static void shouldReturnEmptyList_WhenNoRequests() {
        // When
        System.Test.startTest();
        List<OTSimilarCaseSearch.Response> responses =
            OTSimilarCaseSearch.search(new List<OTSimilarCaseSearch.Request>());
        System.Test.stopTest();

        // Then
        Assert.areEqual(0, responses.size(), 'Empty input yields empty output');
    }
}
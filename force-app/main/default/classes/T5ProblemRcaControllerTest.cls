/**
 * Tests for T5ProblemRcaController — verifies Problem cause breakdown (direct /
 * root cause) and impact-scope counts (corrective 1 / preventive N) assembled from
 * a linked Problem and its Work Orders. Also covers null input and missing-link degrade.
 */
@isTest
private class T5ProblemRcaControllerTest {

    @testSetup
    static void setup() {
        Account acct = new Account(Name = '아이온데이터 테스트');
        insert acct;

        Asset target = new Asset(Name = 'CDU-A-07', AccountId = acct.Id, Status = 'Installed');
        insert target;

        Problem prob = new Problem(
            Subject = 'CDU-A-07 F-07 체결 상태 저하 재발 — 변경 구간 재확인 기준 미반영',
            RootCauseSummary = 'CDU-A-07 Rev.B 변경 구간 F-07의 체결 상태 저하 재발.',
            Description = '조직 차원 근본원인 — 변경·재작업 위치를 이후 점검에서 재확인하는 기준 미비.',
            Workaround = 'F-07 플랜지 재조임 (M16 × 8개소 · 규정 토크 110 N·m)'
        );
        insert prob;

        // 시정조치 1건 + 예방정비 11건 = 12건 (Problem에 연결)
        List<WorkOrder> wos = new List<WorkOrder>();
        wos.add(new WorkOrder(
            AssetId = target.Id, Problem__c = prob.Id,
            Work_Subtype__c = '시정조치', Status = 'New', Subject = '[시정조치] CDU-A-07'
        ));
        for (Integer i = 1; i <= 11; i++) {
            wos.add(new WorkOrder(
                AssetId = target.Id, Problem__c = prob.Id,
                Work_Subtype__c = '예방정비', Status = 'New',
                Subject = '[예방확인] CDU-A-' + String.valueOf(i).leftPad(2, '0')
            ));
        }
        insert wos;

        // 신규사례 Article 근거값용 — 시운전(68→112)·장애복구(71→111) F-07 체결토크
        WorkOrder commissionWo = new WorkOrder(
            AssetId = target.Id, Work_Subtype__c = '시운전', Status = 'New', Subject = '시운전 검사'
        );
        WorkOrder recoveryWo = new WorkOrder(
            AssetId = target.Id, Work_Subtype__c = '장애복구', Status = 'New', Subject = '유량저하 복구'
        );
        insert new List<WorkOrder>{ commissionWo, recoveryWo };

        insert new List<WorkOrderLineItem>{
            new WorkOrderLineItem(
                WorkOrderId = commissionWo.Id, AssetId = target.Id, Line_Item_Role__c = '시험',
                Measurement_Item_Code__c = '체결토크', Measurement_Point__c = 'F-07',
                Measured_Value__c = 68, Judgement__c = '불합격', Retest_Round__c = 1
            ),
            new WorkOrderLineItem(
                WorkOrderId = commissionWo.Id, AssetId = target.Id, Line_Item_Role__c = '시험',
                Measurement_Item_Code__c = '체결토크', Measurement_Point__c = 'F-07',
                Measured_Value__c = 112, Judgement__c = '합격', Retest_Round__c = 2
            ),
            new WorkOrderLineItem(
                WorkOrderId = recoveryWo.Id, AssetId = target.Id, Line_Item_Role__c = '시험',
                Measurement_Item_Code__c = '체결토크', Measurement_Point__c = 'F-07',
                Measured_Value__c = 71, Judgement__c = '불합격', Retest_Round__c = 1
            ),
            new WorkOrderLineItem(
                WorkOrderId = recoveryWo.Id, AssetId = target.Id, Line_Item_Role__c = '시험',
                Measurement_Item_Code__c = '체결토크', Measurement_Point__c = 'F-07',
                Measured_Value__c = 111, Judgement__c = '합격', Retest_Round__c = 2
            )
        };

        insert new Case(
            Subject = 'CDU-A-07 유량 저하', Status = 'New', Priority = 'High',
            AccountId = acct.Id, AssetId = target.Id, Problem__c = prob.Id
        );
        insert new Case(
            Subject = 'Problem 미연결 Case', Status = 'New', Priority = 'Low',
            AccountId = acct.Id, AssetId = target.Id
        );
    }

    private static Id caseIdBySubject(String subject) {
        return [SELECT Id FROM Case WHERE Subject = :subject LIMIT 1].Id;
    }

    @isTest
    static void shouldReturnCauses_WhenProblemLinked() {
        // Given
        Id caseId = caseIdBySubject('CDU-A-07 유량 저하');

        // When
        System.Test.startTest();
        T5ProblemRcaController.ProblemRca result = T5ProblemRcaController.getRca(caseId);
        System.Test.stopTest();

        // Then — 직접 원인=RootCauseSummary, 근본 원인=Description
        Assert.isNotNull(result.problemNumber, 'Problem 번호 반환');
        Assert.isTrue(result.directCause.contains('F-07'), '직접 원인에 F-07');
        Assert.isTrue(result.rootCause.contains('근본원인'), '근본 원인 텍스트 반환');
        Assert.areEqual('F-07 플랜지 재조임 (M16 × 8개소 · 규정 토크 110 N·m)', result.workaround, 'Workaround 반환');
    }

    @isTest
    static void shouldCountScope_1Corrective11Preventive() {
        // Given
        Id caseId = caseIdBySubject('CDU-A-07 유량 저하');

        // When
        System.Test.startTest();
        T5ProblemRcaController.ProblemRca result = T5ProblemRcaController.getRca(caseId);
        System.Test.stopTest();

        // Then — 시정 1 / 예방 11 / 합계 12
        Assert.areEqual(1, result.correctiveCount, '시정조치 1건');
        Assert.areEqual(11, result.preventiveCount, '예방확인 11건');
        Assert.areEqual(12, result.totalCount, '합계 12건');
    }

    @isTest
    static void shouldThrowException_WhenProblemNotLinked() {
        // Given
        Id caseId = caseIdBySubject('Problem 미연결 Case');

        // When / Then — Problem 미연결 Case는 예외
        System.Test.startTest();
        try {
            T5ProblemRcaController.getRca(caseId);
            Assert.fail('Problem 미연결 Case는 예외를 던져야 함');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, '예외 발생 확인');
        }
        System.Test.stopTest();
    }

    @isTest
    static void shouldThrowException_WhenNullCaseId() {
        // When / Then
        System.Test.startTest();
        try {
            T5ProblemRcaController.getRca(null);
            Assert.fail('null Case Id는 예외를 던져야 함');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, '예외 발생 확인');
        }
        System.Test.stopTest();
    }

    @isTest
    static void shouldReturnActions_WithWorkOrdersAndCounts() {
        // Given
        Id caseId = caseIdBySubject('CDU-A-07 유량 저하');

        // When
        System.Test.startTest();
        T5ProblemRcaController.ActionResults result = T5ProblemRcaController.getActions(caseId);
        System.Test.stopTest();

        // Then — 집계 12건 + WO 목록 12건, 시정 1건 플래그
        Assert.areEqual(1, result.correctiveCount, '시정 1건');
        Assert.areEqual(11, result.preventiveCount, '예방 11건');
        Assert.areEqual(12, result.totalCount, '합계 12건');
        Assert.areEqual(12, result.workOrders.size(), 'WO 목록 12건');
        Integer correctiveRows = 0;
        for (T5ProblemRcaController.ActionWorkOrder wo : result.workOrders) {
            if (wo.isCorrective) {
                correctiveRows++;
            }
        }
        Assert.areEqual(1, correctiveRows, '시정 플래그 1건');
    }

    @isTest
    static void shouldBuildArticleEvidence_FromRealMeasurements() {
        // Given
        Id caseId = caseIdBySubject('CDU-A-07 유량 저하');

        // When
        System.Test.startTest();
        T5ProblemRcaController.ActionResults result = T5ProblemRcaController.getActions(caseId);
        System.Test.stopTest();

        // Then — 시운전 68→112, 복구 71→111 실측값이 근거로 조립됨
        T5ProblemRcaController.ArticleEvidence ev = result.articleEvidence;
        Assert.isNotNull(ev, 'Article 근거 존재');
        Assert.areEqual(68, ev.commissionFail, '2022 최초 68');
        Assert.areEqual(112, ev.commissionPass, '2022 재시험 112');
        Assert.areEqual(71, ev.recoveryFail, '2026 최초 71');
        Assert.areEqual(111, ev.recoveryPass, '2026 재시험 111');
    }

    @isTest
    static void shouldThrowException_WhenActionsNullCaseId() {
        // When / Then
        System.Test.startTest();
        try {
            T5ProblemRcaController.getActions(null);
            Assert.fail('null Case Id는 예외를 던져야 함');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, '예외 발생 확인');
        }
        System.Test.stopTest();
    }
}

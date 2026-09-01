/**
 * Tests for T5MeasurementController — 측정 컨텍스트 조회, 측정값 저장, 작업 완료
 * (Status=Completed) 전환, 입력 검증(null) 경로를 검증한다.
 *
 * 판정(Judgement__c)은 이 컨트롤러가 아니라 org의 WOLI_Judgement_AutoSet Flow가
 * 수행하므로, 합격/불합격 테스트는 실제로 그 Flow가 Technical_Baseline_Spec__c를
 * 조회해 판정하는 통합 경로를 검증한다. 그래서 setup에서 승인된 Technical_Baseline과
 * Spec 레코드까지 갖춘 데이터 체인을 만든다.
 */
@isTest
private class T5MeasurementControllerTest {

    @testSetup
    static void setup() {
        // PermissionSetAssignment(setup 객체)와 비setup DML을 같은 트랜잭션에 하면
        // MIXED_DML_OPERATION이 나므로 runAs로 분리한다.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            assignMeasurementAccess();
        }

        Account acct = new Account(Name = 'T5 측정 테스트 고객');
        insert acct;

        Contract contract = new Contract(
            AccountId = acct.Id, Status = 'Draft', StartDate = Date.today(), ContractTerm = 12
        );
        insert contract;

        Customer_Commitment__c commitment = new Customer_Commitment__c(
            Name = 'T5 측정 약속', Contract__c = contract.Id
        );
        insert commitment;

        // 판정 Flow가 스펙을 찾으려면 baseline이 WO에 연결돼야 하고, 검증규칙
        // Block_WO_Without_Approved_Baseline 때문에 baseline은 '승인' 상태여야 한다.
        Technical_Baseline__c baseline = new Technical_Baseline__c(
            Name = 'T5 측정 기준선', Version__c = 'Rev A',
            Contract__c = contract.Id, Customer_Commitment__c = commitment.Id,
            Approval_Status__c = '승인'
        );
        insert baseline;

        insert new List<Technical_Baseline_Spec__c>{
            new Technical_Baseline_Spec__c(
                Technical_Baseline__c = baseline.Id, Measurement_Item_Code__c = '체결토크',
                Threshold_Min__c = 100, Threshold_Max__c = 120, Unit__c = 'N·m', Spec_Value__c = 112
            ),
            new Technical_Baseline_Spec__c(
                Technical_Baseline__c = baseline.Id, Measurement_Item_Code__c = '유량',
                Threshold_Min__c = 2000, Unit__c = 'L/min', Spec_Value__c = 2100
            )
        };

        // WorkOrder에 AssetId를 연결하지 않는다: 측정값 저장이 트렌드 재계산 Flow
        // 체인(WOLI_Trend_Flag_Evaluate → T5_Sync_Asset_Trend_Summary)을 트리거하고,
        // 그 끝의 Apex가 USER_MODE로 Asset을 업데이트해 테스트 사용자 권한으로 실패한다.
        // Asset 미연결 WO면 그 체인이 Asset을 건드리지 않는다. 측정 판정 검증엔 무관.
        WorkOrder wo = new WorkOrder(
            Status = 'New', Subject = '유량저하 복구', Technical_Baseline__c = baseline.Id
        );
        insert wo;

        insert new List<WorkOrderLineItem>{
            new WorkOrderLineItem(
                WorkOrderId = wo.Id, Line_Item_Role__c = '시험',
                Measurement_Item_Code__c = '체결토크', Measurement_Point__c = 'F-07',
                Threshold_Min__c = 100, Threshold_Max__c = 120, Unit__c = 'N·m',
                Previous_Measured_Value__c = 68, Baseline_Value__c = 112, Retest_Round__c = 1
            ),
            new WorkOrderLineItem(
                WorkOrderId = wo.Id, Line_Item_Role__c = '시험',
                Measurement_Item_Code__c = '유량', Measurement_Point__c = '유량',
                Threshold_Min__c = 2000, Unit__c = 'L/min', Retest_Round__c = 1
            )
        };
    }

    /**
     * 측정 필드 FLS(edit)를 현재 실행 사용자에게 부여한다. saveMeasurement의
     * USER_MODE DML이 FLS 없이는 막히므로 테스트 러너 사용자에게도 필요하다.
     */
    private static void assignMeasurementAccess() {
        List<PermissionSet> permSets = [
            SELECT Id FROM PermissionSet WHERE Name = 'T5_WOLI_Measurement_Access' LIMIT 1
        ];
        if (permSets.isEmpty()) {
            return;
        }
        List<PermissionSetAssignment> existing = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :permSets[0].Id
        ];
        if (existing.isEmpty()) {
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(), PermissionSetId = permSets[0].Id
            );
        }
    }

    private static Id getWorkOrderId() {
        return [SELECT Id FROM WorkOrder LIMIT 1].Id;
    }

    private static WorkOrderLineItem getLine(String point) {
        return [
            SELECT Id, Threshold_Min__c, Threshold_Max__c
            FROM WorkOrderLineItem
            WHERE Measurement_Point__c = :point
            LIMIT 1
        ];
    }

    @isTest
    static void shouldReturnLines_WhenContextRequested() {
        Id workOrderId = getWorkOrderId();

        Test.startTest();
        T5MeasurementController.MeasurementContext ctx =
            T5MeasurementController.getContext(workOrderId);
        Test.stopTest();

        Assert.areEqual(2, ctx.lines.size(), '측정 포인트 2건이 반환돼야 한다');
    }

    @isTest
    static void shouldThrow_WhenContextWorkOrderIdNull() {
        Test.startTest();
        try {
            T5MeasurementController.getContext(null);
            Assert.fail('null WorkOrderId는 예외를 던져야 한다');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), '예외 메시지가 있어야 한다');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldPass_WhenValueWithinThreshold() {
        WorkOrderLineItem line = getLine('F-07');

        Test.startTest();
        T5MeasurementController.MeasurementLine result =
            T5MeasurementController.saveMeasurement(line.Id, 111);
        Test.stopTest();

        Assert.isTrue(result.isPass, '111은 100~120 범위 안이므로 합격이어야 한다');
        Assert.areEqual('합격', result.judgement, '판정은 합격이어야 한다');
        WorkOrderLineItem saved = [
            SELECT Measured_Value__c, Judgement__c FROM WorkOrderLineItem WHERE Id = :line.Id
        ];
        Assert.areEqual(111, saved.Measured_Value__c, '측정값이 저장돼야 한다');
        Assert.areEqual('합격', saved.Judgement__c, '판정이 저장돼야 한다');
    }

    @isTest
    static void shouldFail_WhenValueBelowThreshold() {
        WorkOrderLineItem line = getLine('F-07');

        Test.startTest();
        T5MeasurementController.MeasurementLine result =
            T5MeasurementController.saveMeasurement(line.Id, 71);
        Test.stopTest();

        Assert.isFalse(result.isPass, '71은 하한 100 미만이므로 불합격이어야 한다');
        Assert.areEqual('불합격', result.judgement, '판정은 불합격이어야 한다');
    }

    @isTest
    static void shouldFail_WhenValueAboveThreshold() {
        WorkOrderLineItem line = getLine('F-07');

        Test.startTest();
        T5MeasurementController.MeasurementLine result =
            T5MeasurementController.saveMeasurement(line.Id, 130);
        Test.stopTest();

        Assert.isFalse(result.isPass, '130은 상한 120 초과이므로 불합격이어야 한다');
    }

    /**
     * org의 WOLI_Judgement_AutoSet Flow는 판정 시 "값 >= Threshold_Min AND
     * 값 <= Threshold_Max"를 모두 요구한다. 유량 스펙은 상한(Threshold_Max)이
     * 비어 있으므로 값 <= null 비교가 성립하지 않아 불합격으로 판정된다.
     * 즉 이 org에서 상한 미설정 항목은 합격이 될 수 없다(실제 Flow 동작).
     */
    @isTest
    static void shouldFail_WhenMaxThresholdMissing() {
        WorkOrderLineItem line = getLine('유량');

        Test.startTest();
        T5MeasurementController.MeasurementLine result =
            T5MeasurementController.saveMeasurement(line.Id, 2080);
        Test.stopTest();

        Assert.isFalse(result.isPass, '상한 스펙이 없으면 Flow가 불합격으로 판정한다');
    }

    @isTest
    static void shouldThrow_WhenSaveValueNull() {
        WorkOrderLineItem line = getLine('F-07');

        Test.startTest();
        try {
            T5MeasurementController.saveMeasurement(line.Id, null);
            Assert.fail('null 측정값은 예외를 던져야 한다');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), '예외 메시지가 있어야 한다');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldSetCompleted_WhenWorkCompleted() {
        Id workOrderId = getWorkOrderId();

        Test.startTest();
        T5MeasurementController.completeWork(workOrderId);
        Test.stopTest();

        WorkOrder wo = [SELECT Status FROM WorkOrder WHERE Id = :workOrderId];
        Assert.areEqual('Completed', wo.Status, 'WorkOrder는 Completed여야 한다');
    }

    @isTest
    static void shouldThrow_WhenCompleteWorkOrderIdNull() {
        Test.startTest();
        try {
            T5MeasurementController.completeWork(null);
            Assert.fail('null WorkOrderId는 예외를 던져야 한다');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), '예외 메시지가 있어야 한다');
        }
        Test.stopTest();
    }
}

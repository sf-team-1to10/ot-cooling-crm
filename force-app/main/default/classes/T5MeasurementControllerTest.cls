/**
 * Tests for T5MeasurementController — 측정 컨텍스트 조회, 허용구간 판정(합격/불합격),
 * 작업 완료(Status=Completed) 전환, 입력 검증(null) 경로를 검증한다.
 */
@isTest
private class T5MeasurementControllerTest {

    @testSetup
    static void setup() {
        // PermissionSetAssignment(setup 객체)와 Account/WOLI(비setup)를 같은
        // 트랜잭션에 DML하면 MIXED_DML_OPERATION이 나므로 runAs로 분리한다.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            assignMeasurementAccess();
        }

        // WorkOrder에 AssetId를 연결하지 않는다: 측정값 저장이 트렌드 재계산 Flow
        // 체인(WOLI_Trend_Flag_Evaluate → T5_Sync_Asset_Trend_Summary)을 트리거하고,
        // 그 끝의 Apex가 USER_MODE로 Asset을 업데이트해 테스트 사용자 권한으로 실패한다.
        // Asset 미연결 WO면 그 체인이 Asset을 건드리지 않는다. 측정 판정 검증엔 무관.
        WorkOrder wo = new WorkOrder(
            Status = 'New', Subject = '유량저하 복구'
        );
        insert wo;

        // AssetId를 넣지 않는다: WOLI 업데이트가 "T5 Sync Asset Trend Summary" Flow를
        // 트리거하고, 그 Flow가 Asset 필드를 건드려 테스트 사용자 권한으로는 실패하기
        // 때문. 측정 판정 검증에 Asset 연결은 불필요하다.
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

    @isTest
    static void shouldPass_WhenOnlyMinThresholdMet() {
        WorkOrderLineItem line = getLine('유량');

        Test.startTest();
        T5MeasurementController.MeasurementLine result =
            T5MeasurementController.saveMeasurement(line.Id, 2080);
        Test.stopTest();

        Assert.isTrue(result.isPass, '상한 없고 하한 2000 이상이므로 합격이어야 한다');
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

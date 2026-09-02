/**
 * Tests for T5DispatchBriefingController — verifies 12-asset flow comparison
 * (abnormal-first representative selection so a recovered asset still shows its
 * fault state), drift-descending sort, past-failure detection, and Priority rationale.
 */
@isTest
private class T5DispatchBriefingControllerTest {

    @testSetup
    static void setup() {
        Account acct = new Account(Name = '아이온데이터 테스트');
        insert acct;

        // Hall A CDU 3대 (A-07 장애 대상, A-05/A-06 정상 비교군) + Hall B 1대(집계 제외)
        List<Asset> assets = new List<Asset>{
            new Asset(Name = 'CDU-A-07', AccountId = acct.Id, Status = 'Installed', Applied_Revision__c = 'Rev.B'),
            new Asset(Name = 'CDU-A-05', AccountId = acct.Id, Status = 'Installed', Applied_Revision__c = 'Rev.A'),
            new Asset(Name = 'CDU-A-06', AccountId = acct.Id, Status = 'Installed', Applied_Revision__c = 'Rev.A'),
            new Asset(Name = 'CDU-B-01', AccountId = acct.Id, Status = 'Installed', Applied_Revision__c = 'Rev.A')
        };
        insert assets;
        Map<String, Id> assetByName = new Map<String, Id>();
        for (Asset a : assets) {
            assetByName.put(a.Name, a.Id);
        }

        WorkOrder wo07 = new WorkOrder(AssetId = assetByName.get('CDU-A-07'), Work_Subtype__c = '예방정비', Status = 'New');
        WorkOrder wo05 = new WorkOrder(AssetId = assetByName.get('CDU-A-05'), Work_Subtype__c = '예방정비', Status = 'New');
        WorkOrder wo06 = new WorkOrder(AssetId = assetByName.get('CDU-A-06'), Work_Subtype__c = '예방정비', Status = 'New');
        insert new List<WorkOrder>{ wo07, wo05, wo06 };

        // A-07: 과거 불합격(1880/이상) → 이후 회복(2080/정상)이 최신.
        // 컨트롤러는 이상/주의 우선 규칙으로 회복이 아닌 이상 측정을 대표로 잡아야 한다.
        WorkOrderLineItem a07Fault = new WorkOrderLineItem(
            WorkOrderId = wo07.Id, AssetId = assetByName.get('CDU-A-07'), Line_Item_Role__c = '점검',
            Measurement_Item_Code__c = '유량', Measured_Value__c = 1961, Baseline_Value__c = 2100,
            Drift_From_Baseline__c = -6.62, Trend_Flag__c = '이상', Judgement__c = '합격'
        );
        insert a07Fault;
        System.Test.setCreatedDate(a07Fault.Id, Datetime.now().addDays(-10));

        // 과거 시운전 불합격 이력 (hasPastFailure 근거)
        WorkOrderLineItem a07PastFail = new WorkOrderLineItem(
            WorkOrderId = wo07.Id, AssetId = assetByName.get('CDU-A-07'), Line_Item_Role__c = '점검',
            Measurement_Item_Code__c = '유량', Measured_Value__c = 1880, Baseline_Value__c = 2100,
            Drift_From_Baseline__c = -10.48, Trend_Flag__c = '이상', Judgement__c = '불합격'
        );
        insert a07PastFail;
        System.Test.setCreatedDate(a07PastFail.Id, Datetime.now().addDays(-40));

        // A-07 회복값 (최신이지만 정상이라 대표에서 밀려야 함)
        WorkOrderLineItem a07Recovered = new WorkOrderLineItem(
            WorkOrderId = wo07.Id, AssetId = assetByName.get('CDU-A-07'), Line_Item_Role__c = '점검',
            Measurement_Item_Code__c = '유량', Measured_Value__c = 2080, Baseline_Value__c = 2100,
            Drift_From_Baseline__c = -0.95, Trend_Flag__c = '정상', Judgement__c = '합격'
        );
        insert a07Recovered;

        // A-05, A-06 정상
        insert new WorkOrderLineItem(
            WorkOrderId = wo05.Id, AssetId = assetByName.get('CDU-A-05'), Line_Item_Role__c = '점검',
            Measurement_Item_Code__c = '유량', Measured_Value__c = 2075, Baseline_Value__c = 2098,
            Drift_From_Baseline__c = -1.1, Trend_Flag__c = '정상', Judgement__c = '합격'
        );
        insert new WorkOrderLineItem(
            WorkOrderId = wo06.Id, AssetId = assetByName.get('CDU-A-06'), Line_Item_Role__c = '점검',
            Measurement_Item_Code__c = '유량', Measured_Value__c = 2085, Baseline_Value__c = 2102,
            Drift_From_Baseline__c = -0.8, Trend_Flag__c = '정상', Judgement__c = '합격'
        );

        // 대상 Case (A-07)
        Case c = new Case(
            Subject = 'CDU-A-07 유량 저하', Status = 'New', Priority = 'Medium',
            AccountId = acct.Id, AssetId = assetByName.get('CDU-A-07'),
            Impact_Level__c = 'S2 중요',
            Dispatch_Briefing__c = 'A-07 우선 출동 권고',
            Similar_Cases_Summary__c = '동종 장비 유사사례 3건'
        );
        insert c;
    }

    private static Id targetCaseId() {
        return [SELECT Id FROM Case WHERE Subject = 'CDU-A-07 유량 저하' LIMIT 1].Id;
    }

    @isTest
    static void shouldSelectAbnormalRepresentative_WhenAssetRecovered() {
        // Given
        Id caseId = targetCaseId();

        // When
        System.Test.startTest();
        T5DispatchBriefingController.DispatchBriefing b = T5DispatchBriefingController.getBriefing(caseId);
        System.Test.stopTest();

        // Then — A-07 대표값이 회복(-0.95)이 아니라 이상(-6.62)이어야 한다
        T5DispatchBriefingController.AssetComparison a07 = null;
        for (T5DispatchBriefingController.AssetComparison cmp : b.comparisons) {
            if (cmp.assetName == 'CDU-A-07') {
                a07 = cmp;
            }
        }
        // 대표값은 회복(정상, -0.95)이 아니라 장애 측정이어야 한다.
        // org의 Trend 재계산 Flow가 이상↔주의를 정하므로 trend는 '정상만 아님'으로 검증한다.
        Assert.isNotNull(a07, 'A-07 비교 행이 있어야 함');
        Assert.areNotEqual('정상', a07.trendFlag, 'A-07 대표는 회복(정상)이 아닌 장애 측정이어야 함');
        Assert.isTrue(a07.driftFromBaseline < -1.0, 'A-07 대표 하락폭은 회복값(-0.95)보다 커야 함');
        Assert.isTrue(a07.hasPastFailure, 'A-07은 과거 불합격 이력 있음');
    }

    @isTest
    static void shouldSortByDriftDescending_WhenMultipleAssets() {
        // Given
        Id caseId = targetCaseId();

        // When
        System.Test.startTest();
        T5DispatchBriefingController.DispatchBriefing b = T5DispatchBriefingController.getBriefing(caseId);
        System.Test.stopTest();

        // Then — Hall A 3대만 집계(B 제외), 하락폭 큰 순 = A-07 먼저
        Assert.areEqual(3, b.comparisons.size(), 'Hall A CDU 3대만 비교(B 제외)');
        Assert.areEqual('CDU-A-07', b.comparisons[0].assetName, '가장 큰 하락폭 A-07이 맨 위');
        Assert.isTrue(
            b.comparisons[0].driftFromBaseline <= b.comparisons[1].driftFromBaseline,
            '하락폭 오름차순(더 음수가 먼저)'
        );
    }

    @isTest
    static void shouldBuildPriorityRationale_WithMaxDriftAsset() {
        // Given
        Id caseId = targetCaseId();

        // When
        System.Test.startTest();
        T5DispatchBriefingController.DispatchBriefing b = T5DispatchBriefingController.getBriefing(caseId);
        System.Test.stopTest();

        // Then
        T5DispatchBriefingController.PriorityRationale r = b.priorityRationale;
        Assert.isNotNull(r, 'Priority 근거가 있어야 함');
        Assert.areEqual('CDU-A-07', r.maxDriftAssetName, '최대 하락 장비 A-07');
        Assert.areEqual(-6.62, r.maxDriftValue, '최대 하락폭 -6.62');
        Assert.isTrue(r.hasPastFailure, '최대 하락 장비의 과거 실패 이력 true');
        Assert.areEqual(3, r.comparedCount, '비교 대수 3');
        Assert.areEqual('S2 중요', r.impactLevel, 'Impact Level 승계');
    }

    @isTest
    static void shouldReturnCaseFields_WhenValidCase() {
        // Given
        Id caseId = targetCaseId();

        // When
        System.Test.startTest();
        T5DispatchBriefingController.DispatchBriefing b = T5DispatchBriefingController.getBriefing(caseId);
        System.Test.stopTest();

        // Then
        Assert.areEqual('CDU-A-07 유량 저하', b.subject, 'Case Subject 반환');
        Assert.areEqual('CDU-A-07', b.targetAssetName, '대상 Asset명 반환');
        Assert.areEqual('A-07 우선 출동 권고', b.briefingBody, '브리핑 본문 반환');
        Assert.areEqual('동종 장비 유사사례 3건', b.similarCasesSummary, '유사사례 요약 반환');
    }

    @isTest
    static void shouldThrowException_WhenNullCaseId() {
        // When / Then
        System.Test.startTest();
        try {
            T5DispatchBriefingController.getBriefing(null);
            Assert.fail('null Case Id는 예외를 던져야 함');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, '예외 발생 확인');
        }
        System.Test.stopTest();
    }

    @isTest
    static void shouldStartUnapproved_WhenNotYetApproved() {
        // Given
        Id caseId = targetCaseId();

        // When
        System.Test.startTest();
        T5DispatchBriefingController.DispatchBriefing b = T5DispatchBriefingController.getBriefing(caseId);
        System.Test.stopTest();

        // Then — 승인 전엔 isApproved=false, 시각/승인자 비어있음
        Assert.isFalse(b.isApproved, '초기 상태는 미승인');
        Assert.isNull(b.approvedAt, '승인 시각 없음');
        Assert.isNull(b.approvedByName, '승인자 없음');
    }

    @isTest
    static void shouldRecordApproval_WhenApproveDispatch() {
        // Given
        Id caseId = targetCaseId();

        // When
        System.Test.startTest();
        T5DispatchBriefingController.approveDispatch(caseId);
        System.Test.stopTest();

        // Then — 승인 후 조회 시 승인자·시각이 기록되고 isApproved=true
        T5DispatchBriefingController.DispatchBriefing b = T5DispatchBriefingController.getBriefing(caseId);
        Assert.isTrue(b.isApproved, '승인 후 isApproved=true');
        Assert.isNotNull(b.approvedAt, '승인 시각 기록됨');
        Assert.isNotNull(b.approvedByName, '승인자 이름 기록됨');
    }

    @isTest
    static void shouldThrowException_WhenApproveNullCaseId() {
        // When / Then
        System.Test.startTest();
        try {
            T5DispatchBriefingController.approveDispatch(null);
            Assert.fail('null Case Id 승인은 예외를 던져야 함');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, '예외 발생 확인');
        }
        System.Test.stopTest();
    }
}
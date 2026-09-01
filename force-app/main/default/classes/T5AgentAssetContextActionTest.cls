/**
 * T5AgentAssetContextAction 테스트.
 *
 * 이 액션은 콜아웃·async 없이 Asset·WorkOrder·WorkOrderLineItem을 실시간
 * 조회하는 순수 SOQL 로직이라, 실제 테스트 데이터를 세팅해 각 경로를 태운다.
 *
 * ⚠ execute() 전체 경로는 sessionId → MessagingSession.Asset_Id__c로 자산을
 * 찾는데, MessagingSession 레코드 생성은 org의 메시징 채널 설정에 의존적이라
 * 테스트에서 안정적으로 만들 수 없다. 그래서 자산 해석에 의존하지 않는 public
 * helper(resolveGaugesForAgent/pickPrimary/formatGaugesSummary 등)를 직접 태워
 * 게이지·요약·기간 계산 로직 전부를 커버하고, sessionId 경로는 "자산 못 찾음"
 * 분기(found=false)로 검증한다.
 */
@IsTest
private class T5AgentAssetContextActionTest {

    @TestSetup
    static void setup() {
        Account acct = TestDataFactory.createAccount('OT Cooling Test', true);
        Product2 prod = TestDataFactory.createProduct('CDU-Model-X', true);
        Asset asset = TestDataFactory.createAssetForProduct(
            acct.Id, prod.Id, 'CDU-A-07', true
        );
        asset.Warranty_Type__c = '기본보증';
        asset.Open_Items_Summary__c = 2;
        update asset;
    }

    private static Asset getAsset() {
        return [SELECT Id, Name FROM Asset LIMIT 1];
    }

    /**
     * assetId 하나에 대해 측정 회차(WorkOrder)와 항목별 측정값(WOLI)을 만든다.
     * @param flagByCode 측정 항목 코드 → Trend_Flag__c (정상/주의/이상)
     */
    private static WorkOrder buildReadings(
        Id assetId,
        Map<String, String> flagByCode,
        Date startDate
    ) {
        WorkOrder wo = new WorkOrder(
            AssetId = assetId,
            Status = 'New',
            StartDate = startDate
        );
        insert wo;
        List<WorkOrderLineItem> items = new List<WorkOrderLineItem>();
        for (String code : flagByCode.keySet()) {
            items.add(new WorkOrderLineItem(
                WorkOrderId = wo.Id,
                Measurement_Item_Code__c = code,
                Measured_Value__c = 2200,
                Baseline_Value__c = 2000,
                Previous_Measured_Value__c = 2100,
                Delta_From_Previous__c = 100,
                Trend_Flag__c = flagByCode.get(code)
            ));
        }
        insert items;
        return wo;
    }

    @IsTest
    static void resolveGauges_returnsAllItems_WhenReadingsExist() {
        Asset a = getAsset();
        buildReadings(
            a.Id,
            new Map<String, String>{ '유량' => '이상', '수온' => '정상' },
            Date.today()
        );

        Test.startTest();
        List<T5AgentAssetContextAction.GaugeInfo> gauges =
            T5AgentAssetContextAction.resolveGaugesForAgent(a.Id);
        Test.stopTest();

        Assert.areEqual(2, gauges.size(),
            '측정된 두 항목이 모두 반환되어야 한다(정상 항목도 포함)');
    }

    @IsTest
    static void pickPrimary_prefersAbnormalByPriority() {
        // 유량(이상)과 수온(이상)이 둘 다 abnormal이면 우선순위상 유량이 primary.
        Asset a = getAsset();
        buildReadings(
            a.Id,
            new Map<String, String>{ '수온' => '이상', '유량' => '이상' },
            Date.today()
        );

        Test.startTest();
        List<T5AgentAssetContextAction.GaugeInfo> gauges =
            T5AgentAssetContextAction.resolveGaugesForAgent(a.Id);
        T5AgentAssetContextAction.GaugeInfo primary =
            T5AgentAssetContextAction.pickPrimary(gauges);
        Test.stopTest();

        Assert.areEqual('유량', primary.measurementItemCode,
            'abnormal 항목 중 우선순위(유량>차압>수온) 상위가 primary여야 한다');
        Assert.isTrue(primary.abnormal, 'primary는 abnormal이어야 한다');
    }

    @IsTest
    static void pickPrimary_fallsBackToPriorityOrder_WhenAllNormal() {
        Asset a = getAsset();
        buildReadings(
            a.Id,
            new Map<String, String>{ '수온' => '정상', '차압' => '정상' },
            Date.today()
        );

        Test.startTest();
        List<T5AgentAssetContextAction.GaugeInfo> gauges =
            T5AgentAssetContextAction.resolveGaugesForAgent(a.Id);
        T5AgentAssetContextAction.GaugeInfo primary =
            T5AgentAssetContextAction.pickPrimary(gauges);
        Test.stopTest();

        Assert.areEqual('차압', primary.measurementItemCode,
            'abnormal이 없으면 우선순위 순(차압이 수온보다 앞)의 첫 항목이 primary');
    }

    @IsTest
    static void pickPrimary_returnsNull_WhenEmpty() {
        Test.startTest();
        T5AgentAssetContextAction.GaugeInfo primary =
            T5AgentAssetContextAction.pickPrimary(
                new List<T5AgentAssetContextAction.GaugeInfo>()
            );
        T5AgentAssetContextAction.GaugeInfo primaryNull =
            T5AgentAssetContextAction.pickPrimary(null);
        Test.stopTest();

        Assert.isNull(primary, '빈 목록이면 null');
        Assert.isNull(primaryNull, 'null 입력이면 null');
    }

    @IsTest
    static void formatGaugesSummary_includesValueBaselineAndTrend() {
        Asset a = getAsset();
        buildReadings(
            a.Id,
            new Map<String, String>{ '유량' => '이상' },
            Date.today()
        );

        Test.startTest();
        List<T5AgentAssetContextAction.GaugeInfo> gauges =
            T5AgentAssetContextAction.resolveGaugesForAgent(a.Id);
        String summary = T5AgentAssetContextAction.formatGaugesSummary(gauges);
        Test.stopTest();

        Assert.isTrue(summary.contains('유량'), '항목 코드가 요약에 들어가야 한다');
        Assert.isTrue(summary.contains('L/min'), '유량 단위가 표기되어야 한다');
        Assert.isTrue(summary.contains('이상'), '추세 플래그가 요약에 들어가야 한다');
    }

    @IsTest
    static void formatGaugesSummary_returnsPlaceholder_WhenEmpty() {
        Test.startTest();
        String emptySummary = T5AgentAssetContextAction.formatGaugesSummary(
            new List<T5AgentAssetContextAction.GaugeInfo>()
        );
        String nullSummary = T5AgentAssetContextAction.formatGaugesSummary(null);
        Test.stopTest();

        Assert.isTrue(emptySummary.contains('측정 이력이 아직 없습니다'),
            '측정 이력이 없으면 안내 문구를 반환');
        Assert.isTrue(nullSummary.contains('측정 이력이 아직 없습니다'),
            'null이면 안내 문구를 반환');
    }

    @IsTest
    static void formatBaselineRange_returnsTolerantBand() {
        T5AgentAssetContextAction.GaugeInfo g =
            new T5AgentAssetContextAction.GaugeInfo();
        g.measurementItemCode = '유량';
        g.baselineValue = 2000;

        Test.startTest();
        String range = T5AgentAssetContextAction.formatBaselineRange(g);
        Test.stopTest();

        // ±10% of 2000 = ±200 → 1800–2200
        Assert.areEqual('1800–2200 L/min', range,
            '기준선 ±10% 범위가 단위와 함께 표기되어야 한다');
    }

    @IsTest
    static void formatBaselineRange_returnsNull_WhenNoBaseline() {
        T5AgentAssetContextAction.GaugeInfo g =
            new T5AgentAssetContextAction.GaugeInfo();
        g.measurementItemCode = '유량';

        Test.startTest();
        String range = T5AgentAssetContextAction.formatBaselineRange(g);
        String nullRange = T5AgentAssetContextAction.formatBaselineRange(null);
        Test.stopTest();

        Assert.isNull(range, '기준선 값이 없으면 null');
        Assert.isNull(nullRange, 'null 게이지면 null');
    }

    @IsTest
    static void formatMaintenanceHistory_summarizesCompletedWorkOrders() {
        Asset a = getAsset();
        WorkOrder wo = new WorkOrder(
            AssetId = a.Id,
            Status = 'Completed',
            Subject = '정기 점검',
            StartDate = Date.today().addDays(-5)
        );
        insert wo;

        Test.startTest();
        String history = T5AgentAssetContextAction.formatMaintenanceHistory(a.Id);
        Test.stopTest();

        Assert.isTrue(history.contains('정기 점검'),
            '완료된 WorkOrder의 Subject가 이력에 나와야 한다');
        Assert.isTrue(history.contains('완료'), '완료 표기가 있어야 한다');
    }

    @IsTest
    static void formatMaintenanceHistory_returnsPlaceholder_WhenNone() {
        Asset a = getAsset();

        Test.startTest();
        String history = T5AgentAssetContextAction.formatMaintenanceHistory(a.Id);
        Test.stopTest();

        Assert.isTrue(history.contains('완료된 정비 이력이 없습니다'),
            '완료 이력이 없으면 안내 문구를 반환');
    }

    @IsTest
    static void formatDuration_scalesUnitsByElapsedTime() {
        Test.startTest();
        String justNow = T5AgentAssetContextAction.formatDuration(System.now());
        String minutes = T5AgentAssetContextAction.formatDuration(
            System.now().addMinutes(-30)
        );
        String hours = T5AgentAssetContextAction.formatDuration(
            System.now().addHours(-5)
        );
        String days = T5AgentAssetContextAction.formatDuration(
            System.now().addDays(-3)
        );
        String nullDuration = T5AgentAssetContextAction.formatDuration(null);
        Test.stopTest();

        Assert.areEqual('방금', justNow, '1분 미만은 방금');
        Assert.isTrue(minutes.contains('분'), '60분 미만은 분 단위');
        Assert.isTrue(hours.contains('시간'), '24시간 미만은 시간 단위');
        Assert.isTrue(days.contains('일'), '24시간 이상은 일 단위');
        Assert.isNull(nullDuration, 'null이면 null');
    }

    @IsTest
    static void resolveAssetId_returnsNull_WhenNoSessionAndNoRecentAsset() {
        // 유효한 sessionId도, Asset_Id__c가 채워진 최근 세션도 없으면 null.
        Test.startTest();
        Id resolved = T5AgentAssetContextAction.resolveAssetIdForAgent('');
        Id resolvedBadId =
            T5AgentAssetContextAction.resolveAssetIdForAgent('not-an-id');
        Test.stopTest();

        Assert.isNull(resolved, '빈 sessionId + 자산 세션 없음이면 null');
        Assert.isNull(resolvedBadId, '무효 sessionId + 자산 세션 없음이면 null');
    }

    @IsTest
    static void getContext_returnsNotFound_WhenAssetUnresolvable() {
        // 자산을 못 찾는 경로 → found=false, errorMessage 세팅.
        T5AgentAssetContextAction.AssetContextInput inp =
            new T5AgentAssetContextAction.AssetContextInput();
        inp.sessionId = '';

        Test.startTest();
        List<T5AgentAssetContextAction.AssetContextOutput> outs =
            T5AgentAssetContextAction.getContext(
                new List<T5AgentAssetContextAction.AssetContextInput>{ inp }
            );
        Test.stopTest();

        Assert.areEqual(1, outs.size(), '입력 하나당 출력 하나');
        Assert.areEqual(false, outs[0].found,
            '자산을 못 찾으면 found=false');
    }
}

/**
 * Tests for T5HallDashboardController — verifies Hall A asset aggregation
 * (latest inspection Trend per asset, uninspected fallback, status counts)
 * and preventive-maintenance progress.
 */
@isTest
private class T5HallDashboardControllerTest {

    @testSetup
    static void setup() {
        Account acct = new Account(Name = '아이온데이터 테스트');
        insert acct;

        // Hall A 자산 3대 (+ Hall B 1대는 집계에서 빠져야 함)
        List<Asset> assets = new List<Asset>{
            new Asset(Name = 'CDU-A-01', AccountId = acct.Id, Status = 'Installed'),
            new Asset(Name = 'CDU-A-02', AccountId = acct.Id, Status = 'Installed'),
            new Asset(Name = 'CDU-A-03', AccountId = acct.Id, Status = 'Installed'),
            new Asset(Name = 'CDU-B-01', AccountId = acct.Id, Status = 'Installed')
        };
        insert assets;
        Map<String, Id> assetByName = new Map<String, Id>();
        for (Asset a : assets) {
            assetByName.put(a.Name, a.Id);
        }

        // 예방정비 진행률용 WO 3건 (전부 New로 생성 — 완료 WO에 WOLI를 붙이면
        // org의 WOLI 재계산 Flow가 완료 WO를 재저장하며 증빙 검증에 걸리므로 분리).
        WorkOrder wo1 = new WorkOrder(AssetId = assetByName.get('CDU-A-01'), Work_Subtype__c = '예방정비', Status = 'New');
        WorkOrder wo2 = new WorkOrder(AssetId = assetByName.get('CDU-A-02'), Work_Subtype__c = '예방정비', Status = 'New');
        WorkOrder wo3 = new WorkOrder(AssetId = assetByName.get('CDU-A-03'), Work_Subtype__c = '예방정비', Status = 'New');
        insert new List<WorkOrder>{ wo1, wo2, wo3 };

        // 진행률 = 완료 1 / 전체 3. wo1을 WOLI 붙인 뒤 마지막에 Completed로 전환.
        // A-01: 최신 점검 = 정상 (과거 주의 → 최신 정상). CreatedDate 동일 순간 모호성 → 과거건 고정
        WorkOrderLineItem older = new WorkOrderLineItem(
            WorkOrderId = wo1.Id, AssetId = assetByName.get('CDU-A-01'),
            Line_Item_Role__c = '점검', Measurement_Item_Code__c = '유량', Trend_Flag__c = '주의'
        );
        insert older;
        System.Test.setCreatedDate(older.Id, Datetime.now().addDays(-30));

        WorkOrderLineItem newer = new WorkOrderLineItem(
            WorkOrderId = wo1.Id, AssetId = assetByName.get('CDU-A-01'),
            Line_Item_Role__c = '점검', Measurement_Item_Code__c = '유량', Trend_Flag__c = '정상'
        );
        insert newer;

        // A-02: 이상
        insert new WorkOrderLineItem(
            WorkOrderId = wo2.Id, AssetId = assetByName.get('CDU-A-02'),
            Line_Item_Role__c = '점검', Measurement_Item_Code__c = '유량', Trend_Flag__c = '이상'
        );
        // A-03: 점검 WOLI 없음 → 미점검

        // WOLI 배치가 끝난 뒤 wo1만 완료 처리 → 진행률 1/3.
        // 'Completed'는 증빙 검증 규칙(Block_Completion_Without_Evidence)이 실제
        // 첨부 파일을 요구하므로, 검증 대상이 아닌 'Closed'로 완료 처리한다.
        // 컨트롤러는 Completed·Closed 둘 다 완료로 집계한다.
        wo1.Status = 'Closed';
        update wo1;
    }

    @isTest
    static void aggregatesLatestTrendPerAsset() {
        System.Test.startTest();
        T5HallDashboardController.HallSummary s = T5HallDashboardController.getHallSummary();
        System.Test.stopTest();

        System.assertEquals(3, s.totalAssets, 'Hall A 자산 3대만 집계(B 제외)');
        System.assertEquals(1, s.normalCount, 'A-01 최신 점검이 정상이어야 함(과거 주의 무시)');
        System.assertEquals(0, s.warningCount, '주의는 최신이 아니므로 0');
        System.assertEquals(1, s.criticalCount, 'A-02 이상 1건');
        System.assertEquals(1, s.uninspectedCount, 'A-03 점검 이력 없음 → 미점검 1건');
    }

    @isTest
    static void computesPreventiveProgress() {
        System.Test.startTest();
        T5HallDashboardController.HallSummary s = T5HallDashboardController.getHallSummary();
        System.Test.stopTest();

        System.assertEquals(3, s.preventiveTotal, '예방정비 WO 3건');
        System.assertEquals(1, s.preventiveDone, 'Completed 1건');
        System.assertEquals(33, s.preventiveProgress, '1/3 ≈ 33%');
    }

    @isTest
    static void assetRowsCarryTrend() {
        System.Test.startTest();
        T5HallDashboardController.HallSummary s = T5HallDashboardController.getHallSummary();
        System.Test.stopTest();

        Map<String, String> trendByName = new Map<String, String>();
        for (T5HallDashboardController.AssetRow r : s.assets) {
            trendByName.put(r.name, r.trend);
        }
        System.assertEquals('정상', trendByName.get('CDU-A-01'), 'A-01 최신 정상');
        System.assertEquals('이상', trendByName.get('CDU-A-02'), 'A-02 이상');
        System.assertEquals('미점검', trendByName.get('CDU-A-03'), 'A-03 미점검');
    }
}
/**
 * Syncs each Asset's "latest gauge summary" fields from its
 * WorkOrderLineItem readings (T5-07).
 *
 * 왜 필요한가: 고객 포털(Guest 또는 Customer Community 로그인 유저)은
 * WorkOrderLineItem을 직접 조회할 권한을 못 받는다 — 이 org에서
 * WorkOrderLineItem은 관리자를 제외한 어떤 Profile/Permission Set에도
 * 명시적 Object 권한 부여가 안 된다(2026-08-30 확인: Guest User Profile,
 * 표준 Customer Community User 프로필, 새로 만든 커스텀 Permission Set,
 * Field Service Standard 라이선스를 붙인 Permission Set까지 전부
 * "SObject Type Name: bad value for restricted picklist field:
 * WorkOrderLineItem" 에러로 거부됨 — 관리자조차 이 객체에 대한 명시적
 * ObjectPermissions 레코드가 org에 하나도 없이, 프로필 자체의 전체 데이터
 * 접근 특권으로 우회하고 있을 뿐이었다).
 *
 * 그래서 포털이 원본(WorkOrderLineItem)을 직접 보는 대신, 이 배치가
 * WorkOrderLineItem이 바뀔 때마다 그 Asset의 요약 필드(Latest_Trend_Flag__c,
 * Latest_Gauges_JSON__c)를 미리 계산해 복사해둔다. 포털은 Asset만 읽으면
 * 된다(Asset은 이미 Read 권한 부여 가능함을 확인).
 *
 * 호출 경로: T5_Sync_Asset_Trend_Summary Flow (WorkOrderLineItem, after
 * save, ISCHANGED(Trend_Flag__c)일 때 실행). WOLI_Trend_Flag_Evaluate(T4
 * 소유)가 Trend_Flag__c를 Update DML로 써야 이 조건이 참이 되므로, 두 Flow의
 * 실행 순서와 무관하게 항상 T4 Flow가 실제로 값을 쓴 "다음" 라운드에서만
 * 실행된다 — Flow Trigger Order 설정에 의존하지 않는 설계.
 *
 * `without sharing`: 포털에 직접 노출되는 진입점이 아니라, 내부 Flow에서만
 * 호출되는 순수 백그라운드 동기화 작업이라 시스템 컨텍스트로 실행한다.
 * 게이지 계산 로직 자체는 OtTrendAlertCardController의 것을 재사용하며
 * 중복 구현하지 않는다.
 */
public without sharing class T5SyncAssetTrendSummary {
    @InvocableMethod(
        label='Sync Asset Trend Summary'
        description='WorkOrderLineItem 변경분을 바탕으로 Asset의 게이지 요약 필드를 재계산한다.'
    )
    public static void syncAssetTrendSummary(List<Id> assetIds) {
        Set<Id> uniqueAssetIds = new Set<Id>(assetIds);
        uniqueAssetIds.remove(null);
        if (uniqueAssetIds.isEmpty()) {
            return;
        }

        List<Asset> toUpdate = new List<Asset>();
        for (Id assetId : uniqueAssetIds) {
            List<OtTrendAlertCardController.GaugeView> gauges =
                OtTrendAlertCardController.resolveGauges(assetId);
            String latestTrendFlag =
                OtTrendAlertCardController.resolveLatestTrendFlag(assetId);

            toUpdate.add(new Asset(
                Id = assetId,
                Latest_Trend_Flag__c = latestTrendFlag,
                Latest_Gauges_JSON__c = JSON.serialize(gauges)
            ));
        }
        update toUpdate;
    }
}

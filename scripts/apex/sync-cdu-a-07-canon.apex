// CDU-A-07 정본 값(T1 2026-04-08 장애 시점)으로 최신 WOLI 정합.
// 대상 = T5AgentAssetContextAction이 실제로 읽는 latest non-null WOLI 3건.
// Baseline은 이미 정본 값(2100/112/20)과 동일하므로 명시 세팅만.
List<WorkOrderLineItem> upd = new List<WorkOrderLineItem>();

WorkOrderLineItem flow = new WorkOrderLineItem(
    Id = '1WLbm000000CuZVGA0',
    Measured_Value__c = 1961,
    Baseline_Value__c = 2100,
    Previous_Measured_Value__c = 1976,
    Delta_From_Previous__c = -15,
    Trend_Flag__c = '주의'
);
upd.add(flow);

WorkOrderLineItem torque = new WorkOrderLineItem(
    Id = '1WLbm000000CuZWGA0',
    Measured_Value__c = 71,
    Baseline_Value__c = 112,
    Previous_Measured_Value__c = 71,
    Delta_From_Previous__c = 0,
    Trend_Flag__c = '주의'
);
upd.add(torque);

WorkOrderLineItem temp = new WorkOrderLineItem(
    Id = '1WLbm000000CuZXGA0',
    Measured_Value__c = 20,
    Baseline_Value__c = 20,
    Previous_Measured_Value__c = 20,
    Delta_From_Previous__c = 0,
    Trend_Flag__c = '정상'
);
upd.add(temp);

update upd;

for (WorkOrderLineItem w : [
    SELECT Id, Measurement_Item_Code__c, Measured_Value__c, Baseline_Value__c,
           Previous_Measured_Value__c, Delta_From_Previous__c, Trend_Flag__c
    FROM WorkOrderLineItem
    WHERE Id IN :upd
]) {
    System.debug('AFTER ' + w.Measurement_Item_Code__c + ': ' + w);
}

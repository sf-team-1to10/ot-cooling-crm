#!/bin/bash
# T4-07 막힘 확인 — org 실제 상태 조회 (읽기만, 아무것도 안 바꾼다)
set -u
ORG=T4OPS
echo "=== 1. Flow 활성 상태 (Baseline=T4-05 / Trend=T4-07 / AutoCreate=T4-03) ==="
sf data query -o $ORG -q "SELECT Label, ApiName, IsActive, ProcessType FROM FlowDefinitionView WHERE ApiName IN ('WOLI_Baseline_Prior_Compare','WOLI_Trend_Flag_Evaluate','WO_Maintenance_LineItem_AutoCreate','WO_Commission_LineItem_AutoCreate')"

echo "=== 2. WOLI 라인 실제 존재 여부 (AssetId 필터 없이) ==="
sf data query -o $ORG -q "SELECT Id, WorkOrderId, AssetId, Measurement_Item_Code__c, Line_Item_Role__c, Measured_Value__c, Baseline_Value__c, Delta_From_Previous__c, Drift_From_Baseline__c, Trend_Flag__c, CreatedDate FROM WorkOrderLineItem ORDER BY CreatedDate DESC LIMIT 30"

echo "=== 3. AssetId 누락 라인 수 ==="
sf data query -o $ORG -q "SELECT COUNT(Id) total FROM WorkOrderLineItem WHERE AssetId = null"

echo "=== 4. Retest_Round__c 등 T3-13 필드 배포 여부 ==="
sf sobject describe -s WorkOrderLineItem -o $ORG --json 2>/dev/null \
  | python3 -c "import json,sys; f={x['name'] for x in json.load(sys.stdin)['result']['fields']}; [print(('있음  ' if n in f else '없음  ')+n) for n in ['Retest_Round__c','Retest_Reason__c','Parent_Line_Item__c','Root_Line_Item__c','Corrective_Action__c','Trend_Flag__c','Baseline_Value__c','Delta_From_Previous__c','Drift_From_Baseline__c','Measurement_Item_Code__c','Line_Item_Role__c']]"

echo "=== 5. Trend_Threshold__mdt 레코드 ==="
sf data query -o $ORG -q "SELECT DeveloperName, Drop_Rate_Pct__c, Consecutive_Drops__c, Remaining_Margin_Pct__c FROM Trend_Threshold__mdt"

echo "=== 6. Standard Pricebook ==="
sf data query -o $ORG -q "SELECT Id, Name, IsActive FROM Pricebook2 WHERE IsStandard = true"

echo "=== 7. AssetId 없는 WOLI가 달린 WorkOrder (삭제 대상 확인용) ==="
sf data query -o $ORG -q "SELECT WorkOrderId, WorkOrder.Subject, WorkOrder.Work_Subtype__c, COUNT(Id) cnt FROM WorkOrderLineItem WHERE AssetId = null GROUP BY WorkOrderId, WorkOrder.Subject, WorkOrder.Work_Subtype__c"

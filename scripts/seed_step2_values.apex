// WO 00000197 (최초 측정)
List<WorkOrderLineItem> w1 = [
    SELECT Id, Measurement_Item_Code__c FROM WorkOrderLineItem
    WHERE WorkOrderId = '0WObm000005UacgGAC'
];
for (WorkOrderLineItem w : w1) {
    w.Measurement_Point__c = 'F-07';
    if (w.Measurement_Item_Code__c == '유량') {
        w.Measured_Value__c = 1961; w.Baseline_Value__c = 2100;
        w.Judgement__c = '합격'; w.Trend_Flag__c = '이상';
    } else if (w.Measurement_Item_Code__c == '수온') {
        w.Measured_Value__c = 21; w.Baseline_Value__c = 20; w.Judgement__c = '합격';
    } else if (w.Measurement_Item_Code__c == '차압') {
        w.Measured_Value__c = 0.35; w.Baseline_Value__c = 0.30; w.Judgement__c = '합격';
    } else if (w.Measurement_Item_Code__c == '전류') {
        w.Measured_Value__c = 12.4; w.Baseline_Value__c = 12.0; w.Judgement__c = '합격';
    } else if (w.Measurement_Item_Code__c == '누기') {
        w.Measured_Value__c = 0; w.Baseline_Value__c = 0; w.Judgement__c = '합격';
    } else if (w.Measurement_Item_Code__c == '체결토크') {
        w.Measured_Value__c = 71; w.Baseline_Value__c = 110; w.Judgement__c = '불합격';
    }
}
update w1;
System.debug('WO 197: ' + w1.size());

// WO 00000198 (재시험)
List<WorkOrderLineItem> w2 = [
    SELECT Id, Measurement_Item_Code__c FROM WorkOrderLineItem
    WHERE WorkOrderId = '0WObm000005UachGAC'
];
for (WorkOrderLineItem w : w2) {
    w.Measurement_Point__c = 'F-07';
    if (w.Measurement_Item_Code__c == '유량') {
        w.Measured_Value__c = 2080; w.Baseline_Value__c = 2100; w.Judgement__c = '합격';
    } else if (w.Measurement_Item_Code__c == '수온') {
        w.Measured_Value__c = 20.5; w.Baseline_Value__c = 20; w.Judgement__c = '합격';
    } else if (w.Measurement_Item_Code__c == '차압') {
        w.Measured_Value__c = 0.29; w.Baseline_Value__c = 0.30; w.Judgement__c = '합격';
    } else if (w.Measurement_Item_Code__c == '전류') {
        w.Measured_Value__c = 11.9; w.Baseline_Value__c = 12.0; w.Judgement__c = '합격';
    } else if (w.Measurement_Item_Code__c == '누기') {
        w.Measured_Value__c = 0; w.Baseline_Value__c = 0; w.Judgement__c = '합격';
    } else if (w.Measurement_Item_Code__c == '체결토크') {
        w.Measured_Value__c = 112; w.Baseline_Value__c = 110; w.Judgement__c = '합격';
    }
}
update w2;
System.debug('WO 198: ' + w2.size());

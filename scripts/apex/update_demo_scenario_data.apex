// 최신 WOLI 유량값을 시나리오에 맞춰 1961로 수정
WorkOrderLineItem woli = [SELECT Id, Measured_Value__c, Trend_Flag__c FROM WorkOrderLineItem WHERE Id = '1WLbm000000ChxFGAS'];
woli.Measured_Value__c = 1961;
woli.Trend_Flag__c = '주의';
update woli;
System.debug('WOLI updated: ' + woli.Id + ' → 1961, 주의');

// Asset 스냅샷을 시나리오 값으로 갱신
Asset a = [SELECT Id, Latest_Gauges_JSON__c, Latest_Trend_Flag__c FROM Asset WHERE Id = '02ibm000003uetzAAA'];
a.Latest_Gauges_JSON__c = '[{"trendFlag":"주의","sparklineValues":[2100,2080,2050,2020,2000,1980,1961],"previousValue":2000,"measurementItemCode":"유량","deltaFromPrevious":-39,"currentValue":1961,"baselineValue":2100}]';
a.Latest_Trend_Flag__c = '주의';
update a;
System.debug('Asset updated: gauges=1961/2100/주의');

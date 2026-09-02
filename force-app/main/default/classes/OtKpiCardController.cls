public with sharing class OtKpiCardController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getKpiSummary() {
        Map<String, Integer> kpi = new Map<String, Integer>();

        kpi.put('openCases',    [SELECT COUNT() FROM Case WHERE IsClosed = false WITH USER_MODE]);
        kpi.put('criticalCases',[SELECT COUNT() FROM Case WHERE IsClosed = false AND Priority = 'Critical' WITH USER_MODE]);
        kpi.put('openWorkOrders',[SELECT COUNT() FROM WorkOrder WHERE Status NOT IN ('Completed','Cancelled') WITH USER_MODE]);
        kpi.put('pendingCR',    [SELECT COUNT() FROM ChangeRequest WHERE Status IN ('요청받음','고객승인대기','내부검토중') WITH USER_MODE]);

        return kpi;
    }
}
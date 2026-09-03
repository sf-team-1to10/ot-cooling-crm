public with sharing class OtSalesSidebarController {

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getTodayTasks() {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Task t : [
            SELECT Id, Subject, ActivityDate, Priority, Status, What.Name, WhatId
            FROM Task
            WHERE OwnerId = :UserInfo.getUserId()
              AND Status != 'Completed'
            ORDER BY ActivityDate ASC NULLS LAST
            LIMIT 5
        ]) {
            result.add(new Map<String, Object>{
                'id'        => t.Id,
                'subject'   => t.Subject,
                'dueDate'   => t.ActivityDate != null ? String.valueOf(t.ActivityDate) : null,
                'priority'  => t.Priority,
                'status'    => t.Status,
                'relatedTo' => t.What != null ? t.What.Name : null,
                'relatedId' => t.WhatId
            });
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getTodayEvents() {
        Date today = Date.today();
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Event e : [
            SELECT Id, Subject, StartDateTime, EndDateTime
            FROM Event
            WHERE OwnerId = :UserInfo.getUserId()
              AND ActivityDate = :today
            ORDER BY StartDateTime ASC
            LIMIT 5
        ]) {
            String timeStr = '';
            if (e.StartDateTime != null) {
                Datetime dt = e.StartDateTime;
                timeStr = String.valueOf(dt.hour()).leftPad(2, '0') + ':' + String.valueOf(dt.minute()).leftPad(2, '0');
            }
            result.add(new Map<String, Object>{
                'id'      => e.Id,
                'subject' => e.Subject,
                'time'    => timeStr
            });
        }
        return result;
    }
}

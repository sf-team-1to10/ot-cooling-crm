public with sharing class T5SalesHomeController {
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getSalesHome() {
        List<Map<String, Object>> taskList = new List<Map<String, Object>>();
        for (Task t : [
            SELECT Id, Subject, Status, ActivityDate, What.Name
            FROM Task
            WHERE Status != 'Completed' AND OwnerId = :UserInfo.getUserId()
            ORDER BY ActivityDate ASC
            LIMIT 10
        ]) {
            taskList.add(new Map<String, Object>{
                'id' => t.Id,
                'subject' => t.Subject,
                'status' => t.Status,
                'dueDate' => t.ActivityDate != null ? String.valueOf(t.ActivityDate) : null,
                'relatedTo' => t.What != null ? t.What.Name : '—'
            });
        }

        List<Map<String, Object>> oppList = new List<Map<String, Object>>();
        for (Opportunity o : [
            SELECT Id, Name, StageName, Amount, CloseDate, Account.Name
            FROM Opportunity
            WHERE IsClosed = false AND OwnerId = :UserInfo.getUserId()
            ORDER BY CloseDate ASC
            LIMIT 10
        ]) {
            oppList.add(new Map<String, Object>{
                'id' => o.Id,
                'name' => o.Name,
                'stage' => o.StageName,
                'amount' => o.Amount,
                'closeDate' => o.CloseDate != null ? String.valueOf(o.CloseDate) : null,
                'account' => o.Account != null ? o.Account.Name : '—'
            });
        }

        return new Map<String, Object>{
            'tasks' => taskList,
            'opportunities' => oppList
        };
    }
}

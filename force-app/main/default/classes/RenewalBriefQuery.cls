/**
 * RenewalBriefQuery — Agent Script action (read-only).
 *
 * Wired to the Renewal_Brief_Agent via:  target: "apex://RenewalBriefQuery"
 *
 * Finds a renewal/expansion Opportunity by name and returns the fields the
 * agent needs to compose a meeting brief (service performance summary,
 * residual risk, expansion capacity/timing, description) as a JSON string.
 * Read-only: SELECT only, no DML.
 *
 * T1-24 (PoC ot-t1-renewal-expansion-brief 승격). 근거 필드는 org 실측 확인됨.
 */
public with sharing class RenewalBriefQuery {

    @InvocableMethod(
        label='Query Opportunity for Renewal Brief'
        description='Finds a renewal/expansion Opportunity by name and returns its brief fields (SLA summary, residual risk, expansion capacity/timing, description) as JSON. Read-only.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result r = new Result();
            try {
                String term = (req.opportunityName == null) ? '' : req.opportunityName.trim();
                if (String.isBlank(term)) {
                    r.isSuccess = false;
                    r.errorMessage = 'Opportunity name was not provided.';
                    r.count = 0;
                    r.opportunitiesJson = '[]';
                    results.add(r);
                    continue;
                }

                String pattern = '%' + term + '%';
                List<Opportunity> opps = [
                    SELECT Id, Name, StageName, Type, Account.Name,
                           SLA_Summary__c, Residual_Risk__c,
                           Expansion_Capacity__c, Expansion_Timing__c,
                           Competition__c, Evidence_Link__c, Description
                    FROM Opportunity
                    WHERE Name LIKE :pattern
                    ORDER BY LastModifiedDate DESC
                    LIMIT 10
                ];

                List<Map<String, Object>> rows = new List<Map<String, Object>>();
                for (Opportunity o : opps) {
                    Map<String, Object> row = new Map<String, Object>();
                    row.put('id', o.Id);
                    row.put('name', o.Name);
                    row.put('accountName', o.Account != null ? o.Account.Name : null);
                    row.put('stage', o.StageName);
                    row.put('type', o.Type);
                    row.put('slaSummary', o.SLA_Summary__c);
                    row.put('residualRisk', o.Residual_Risk__c);
                    row.put('expansionCapacity', o.Expansion_Capacity__c);
                    row.put('expansionTiming', o.Expansion_Timing__c);
                    row.put('competition', o.Competition__c);
                    row.put('evidenceLink', o.Evidence_Link__c);
                    row.put('description', o.Description);
                    rows.add(row);
                }

                r.isSuccess = true;
                r.count = rows.size();
                r.opportunitiesJson = JSON.serialize(rows);
            } catch (Exception e) {
                r.isSuccess = false;
                r.errorMessage = e.getMessage();
                r.count = 0;
                r.opportunitiesJson = '[]';
            }
            results.add(r);
        }

        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Opportunity Name'
            description='Full or partial name of the renewal/expansion opportunity to look up.'
            required=true
        )
        public String opportunityName;
    }

    public class Result {
        @InvocableVariable(
            label='Is Success'
            description='Whether the query succeeded'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Error Message'
            description='Error message if the query failed'
        )
        public String errorMessage;

        @InvocableVariable(
            label='Opportunity Count'
            description='Number of matching opportunities returned'
        )
        public Integer count;

        @InvocableVariable(
            label='Opportunities JSON'
            description='Opportunities as a JSON array string: id, name, accountName, stage, type, slaSummary, residualRisk, expansionCapacity, expansionTiming, competition, evidenceLink, description'
        )
        public String opportunitiesJson;
    }
}

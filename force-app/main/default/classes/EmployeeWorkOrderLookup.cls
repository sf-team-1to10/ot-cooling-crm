/**
 * EmployeeWorkOrderLookup — Agent Script action (read-only).
 *
 * Wired to the Employee_Ops_Agent (T5-29 작업 완료 보고 Topic) via:
 *   target: "apex://EmployeeWorkOrderLookup"
 *
 * Given a free-text hint from a natural-language completion report
 * (e.g. "CDU-A-07 조치 완료"), returns candidate WorkOrders so the agent can
 * IDENTIFY which WO the report refers to — and, when ambiguous, ask the user
 * to disambiguate. Read-only: SELECT only, no DML. The actual status update
 * (write) is a separate, human-gated step and is NOT implemented here.
 *
 * T5-29 (트랙 C · 09-t5-task-cycle). 실제 필드명은 org describe로 확인됨.
 */
public with sharing class EmployeeWorkOrderLookup {

    @InvocableMethod(
        label='Lookup Candidate Work Orders'
        description='Returns open/in-progress WorkOrders matching a free-text hint (asset name, subject) as JSON, for identifying which WO a completion report refers to. Read-only.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result r = new Result();
            try {
                Integer maxRows = (req.maxResults == null || req.maxResults <= 0)
                    ? 10 : req.maxResults;

                String term = req.searchText == null ? '' : req.searchText.trim();
                String pattern = '%' + term + '%';

                List<WorkOrder> wos;
                if (String.isBlank(term)) {
                    wos = [
                        SELECT Id, WorkOrderNumber, Subject, Status, AssetId, Asset.Name, CaseId, CreatedDate
                        FROM WorkOrder
                        WHERE Status != 'Closed' AND Status != 'Cannot Complete'
                        ORDER BY CreatedDate DESC
                        LIMIT 200
                    ];
                } else {
                    wos = [
                        SELECT Id, WorkOrderNumber, Subject, Status, AssetId, Asset.Name, CaseId, CreatedDate
                        FROM WorkOrder
                        WHERE (Status != 'Closed' AND Status != 'Cannot Complete')
                          AND (Subject LIKE :pattern OR Asset.Name LIKE :pattern)
                        ORDER BY CreatedDate DESC
                        LIMIT 200
                    ];
                }

                List<Map<String, Object>> rows = new List<Map<String, Object>>();
                for (WorkOrder w : wos) {
                    Map<String, Object> row = new Map<String, Object>();
                    row.put('id', w.Id);
                    row.put('workOrderNumber', w.WorkOrderNumber);
                    row.put('subject', w.Subject);
                    row.put('status', w.Status);
                    row.put('assetId', w.AssetId);
                    row.put('assetName', w.Asset != null ? w.Asset.Name : null);
                    row.put('caseId', w.CaseId);
                    row.put('createdDate', w.CreatedDate);
                    rows.add(row);
                    if (rows.size() >= maxRows) {
                        break;
                    }
                }

                r.isSuccess = true;
                r.count = rows.size();
                r.workOrdersJson = JSON.serialize(rows);
            } catch (Exception e) {
                r.isSuccess = false;
                r.errorMessage = e.getMessage();
                r.count = 0;
                r.workOrdersJson = '[]';
            }
            results.add(r);
        }

        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Search Text'
            description='Free-text hint from the completion report (asset name or subject keyword). Blank returns all open WOs.'
            required=false
        )
        public String searchText;

        @InvocableVariable(
            label='Max Results'
            description='Maximum number of candidate WorkOrders to return. Defaults to 10.'
            required=false
        )
        public Integer maxResults;
    }

    public class Result {
        @InvocableVariable(label='Is Success' description='Whether the query succeeded')
        public Boolean isSuccess;

        @InvocableVariable(label='Error Message' description='Error message if the query failed')
        public String errorMessage;

        @InvocableVariable(label='Count' description='Number of candidate WorkOrders returned')
        public Integer count;

        @InvocableVariable(
            label='Work Orders JSON'
            description='Candidate WorkOrders as JSON array: id, workOrderNumber, subject, status, assetId, assetName, caseId, createdDate'
        )
        public String workOrdersJson;
    }
}

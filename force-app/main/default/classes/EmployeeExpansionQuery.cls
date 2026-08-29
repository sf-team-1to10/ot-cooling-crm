/**
 * EmployeeExpansionQuery — Agent Script action (read-only).
 *
 * Wired to the Employee_Ops_Agent (T5-28 증설 제안 초안 Topic) via:
 *   target: "apex://EmployeeExpansionQuery"
 *
 * Given an Account (Hall/고객), returns the facts a 증설 제안 초안 needs:
 * contract expiry dates, recent Case history, and installed Assets — as a
 * JSON string so the agent can synthesize a DRAFT proposal in its reasoning.
 * Read-only: SELECT only, no DML. The agent must stop at 초안 — no send/commit.
 *
 * T5-28 (트랙 C · 09-t5-task-cycle). 실제 필드명은 org describe로 확인됨.
 */
public with sharing class EmployeeExpansionQuery {

    @InvocableMethod(
        label='Query Expansion Proposal Facts'
        description='Returns contract expiry, recent cases, and assets for an account as JSON, for an expansion-proposal draft. Read-only.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result r = new Result();
            try {
                if (String.isBlank(req.accountId)) {
                    r.isSuccess = false;
                    r.errorMessage = 'accountId is required.';
                    r.dataJson = '{}';
                    results.add(r);
                    continue;
                }

                List<Contract> contracts = [
                    SELECT Id, ContractNumber, Status, StartDate, EndDate
                    FROM Contract
                    WHERE AccountId = :req.accountId
                    ORDER BY EndDate DESC NULLS LAST
                    LIMIT 50
                ];

                List<Case> cases = [
                    SELECT Id, CaseNumber, Subject, Status, Priority, AssetId, CreatedDate, ClosedDate
                    FROM Case
                    WHERE AccountId = :req.accountId
                    ORDER BY CreatedDate DESC
                    LIMIT 50
                ];

                List<Asset> assets = [
                    SELECT Id, Name, Product2.Name, Status, InstallDate
                    FROM Asset
                    WHERE AccountId = :req.accountId
                    ORDER BY Name
                    LIMIT 200
                ];

                List<Map<String, Object>> contractRows = new List<Map<String, Object>>();
                for (Contract c : contracts) {
                    Map<String, Object> row = new Map<String, Object>();
                    row.put('id', c.Id);
                    row.put('contractNumber', c.ContractNumber);
                    row.put('status', c.Status);
                    row.put('startDate', c.StartDate);
                    row.put('endDate', c.EndDate);
                    contractRows.add(row);
                }

                List<Map<String, Object>> caseRows = new List<Map<String, Object>>();
                for (Case c : cases) {
                    Map<String, Object> row = new Map<String, Object>();
                    row.put('id', c.Id);
                    row.put('caseNumber', c.CaseNumber);
                    row.put('subject', c.Subject);
                    row.put('status', c.Status);
                    row.put('priority', c.Priority);
                    row.put('assetId', c.AssetId);
                    row.put('createdDate', c.CreatedDate);
                    row.put('closedDate', c.ClosedDate);
                    caseRows.add(row);
                }

                List<Map<String, Object>> assetRows = new List<Map<String, Object>>();
                for (Asset a : assets) {
                    Map<String, Object> row = new Map<String, Object>();
                    row.put('id', a.Id);
                    row.put('name', a.Name);
                    row.put('product', a.Product2 != null ? a.Product2.Name : null);
                    row.put('status', a.Status);
                    row.put('installDate', a.InstallDate);
                    assetRows.add(row);
                }

                Map<String, Object> data = new Map<String, Object>();
                data.put('contracts', contractRows);
                data.put('cases', caseRows);
                data.put('assets', assetRows);

                r.isSuccess = true;
                r.contractCount = contractRows.size();
                r.caseCount = caseRows.size();
                r.assetCount = assetRows.size();
                r.dataJson = JSON.serialize(data);
            } catch (Exception e) {
                r.isSuccess = false;
                r.errorMessage = e.getMessage();
                r.dataJson = '{}';
            }
            results.add(r);
        }

        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Account Id'
            description='The Account (고객/Hall) to gather expansion-proposal facts for.'
            required=true
        )
        public String accountId;
    }

    public class Result {
        @InvocableVariable(label='Is Success' description='Whether the query succeeded')
        public Boolean isSuccess;

        @InvocableVariable(label='Error Message' description='Error message if the query failed')
        public String errorMessage;

        @InvocableVariable(label='Contract Count' description='Number of contracts returned')
        public Integer contractCount;

        @InvocableVariable(label='Case Count' description='Number of cases returned')
        public Integer caseCount;

        @InvocableVariable(label='Asset Count' description='Number of assets returned')
        public Integer assetCount;

        @InvocableVariable(
            label='Data JSON'
            description='Facts as JSON object: contracts[], cases[], assets[] for the account'
        )
        public String dataJson;
    }
}

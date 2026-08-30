public without sharing class T5AgentCaseIntakeAction {

    @InvocableMethod(
        label='Create Case from Agent Consultation'
        description='Agent가 고객 대화에서 파악한 증상·영향을 기존 Case 생성 로직으로 접수한다. 폼(otReportFault)과 동일한 필드·자동화를 탄다.'
    )
    public static List<CaseOutput> createCase(List<CaseInput> inputs) {
        List<CaseOutput> results = new List<CaseOutput>();
        for (CaseInput inp : inputs) {
            results.add(execute(inp));
        }
        return results;
    }

    private static CaseOutput execute(CaseInput inp) {
        CaseOutput out = new CaseOutput();

        if (String.isBlank(inp.assetId)) {
            out.success = false;
            out.errorMessage = '자산이 선택되지 않았습니다.';
            return out;
        }
        if (String.isBlank(inp.symptomCategory)) {
            out.success = false;
            out.errorMessage = '증상 분류가 필요합니다.';
            return out;
        }
        if (String.isBlank(inp.impactLevel)) {
            out.success = false;
            out.errorMessage = '영향 등급이 필요합니다.';
            return out;
        }
        if (String.isBlank(inp.reportedSymptom)) {
            out.success = false;
            out.errorMessage = '고객 진술이 필요합니다.';
            return out;
        }

        try {
            Id assetId = Id.valueOf(inp.assetId);
            List<Asset> assets = [
                SELECT Id, AccountId FROM Asset
                WHERE Id = :assetId LIMIT 1
            ];
            if (assets.isEmpty()) {
                out.success = false;
                out.errorMessage = '자산을 찾을 수 없습니다: ' + inp.assetId;
                return out;
            }
            Asset asset = assets[0];

            Id contactId = resolveContact(inp.contactId, asset.AccountId);

            Case newCase = new Case(
                AssetId = assetId,
                AccountId = asset.AccountId,
                ContactId = contactId,
                Origin = 'Agent',
                Subject = inp.symptomCategory,
                Symptom_Category__c = inp.symptomCategory,
                Impact_Level__c = inp.impactLevel,
                Reported_Symptom__c = inp.reportedSymptom
            );
            insert newCase;

            Case saved = [
                SELECT CaseNumber, Account.Name,
                       Warranty_Decision__c, Coverage_Type__c, Billable__c
                FROM Case WHERE Id = :newCase.Id LIMIT 1
            ];

            out.success = true;
            out.caseId = saved.Id;
            out.caseNumber = saved.CaseNumber;
            out.accountName = saved.Account != null ? saved.Account.Name : '';
            out.warrantyDecision = saved.Warranty_Decision__c;
            out.coverageType = saved.Coverage_Type__c;
            out.billable = saved.Billable__c;
        } catch (Exception e) {
            out.success = false;
            out.errorMessage = e.getMessage();
        }
        return out;
    }

    private static Id resolveContact(String contactIdStr, Id accountId) {
        if (String.isNotBlank(contactIdStr)) {
            try {
                return Id.valueOf(contactIdStr);
            } catch (Exception e) { /* fall through */ }
        }
        List<Contact> contacts = [
            SELECT Id FROM Contact
            WHERE AccountId = :accountId
            ORDER BY CreatedDate ASC LIMIT 1
        ];
        return contacts.isEmpty() ? null : contacts[0].Id;
    }

    public class CaseInput {
        @InvocableVariable(label='Asset Id' description='장애 대상 자산의 Salesforce Id' required=true)
        public String assetId;

        @InvocableVariable(label='Symptom Category' description='증상 분류 (유량저하/누수/소음/제어이상/전원/기타)' required=true)
        public String symptomCategory;

        @InvocableVariable(label='Impact Level' description='영향 등급 (S1 긴급/S2 중요/S3 일반/S4 요청)' required=true)
        public String impactLevel;

        @InvocableVariable(label='Reported Symptom' description='고객이 설명한 증상 원문' required=true)
        public String reportedSymptom;

        @InvocableVariable(label='Contact Id' description='고객 담당자 Id (선택, 없으면 Account의 첫 Contact 사용)')
        public String contactId;
    }

    public class CaseOutput {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Case Id')
        public String caseId;

        @InvocableVariable(label='Case Number')
        public String caseNumber;

        @InvocableVariable(label='Account Name')
        public String accountName;

        @InvocableVariable(label='Warranty Decision')
        public String warrantyDecision;

        @InvocableVariable(label='Coverage Type')
        public String coverageType;

        @InvocableVariable(label='Billable')
        public Boolean billable;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }
}

/**
 * Customer 360 데이터 공급 컨트롤러 (T5-25).
 * Case Id를 받아 그 고객사(Account) 기준으로 계약·제품·문제·영업 4개 섹션을
 * 하나의 DTO로 묶어 반환한다. MIAW 2차 인수 시점에 서정비가 한 화면에서
 * 고객 전체 맥락을 확인하는 용도.
 * Callable from the t5Customer360 LWC via @wire.
 */
public with sharing class T5Customer360Controller {

    /**
     * 현재 Case 기준으로 고객 360 데이터를 조립한다.
     * @param caseId 조회 기준 Case Id
     * @return 계약·제품·문제·영업 4섹션을 담은 Customer360
     */
    @AuraEnabled(cacheable=true)
    public static Customer360 getCustomer360(Id caseId) {
        Case current = getCurrentCase(caseId);
        Id accountId = current.AccountId;

        Customer360 result = new Customer360();
        result.accountName = current.Account?.Name;
        result.currentEntitlementId = current.EntitlementId;

        if (accountId == null) {
            return result;
        }

        result.profile = buildProfile(current);
        result.contracts = buildContracts(accountId, current.EntitlementId);
        result.assets = buildAssets(accountId);
        result.pastCases = buildPastCases(accountId, caseId);
        result.opportunities = buildOpportunities(accountId);
        return result;
    }

    // ─── Section builders ────────────────────────────────────────────────

    private static Case getCurrentCase(Id caseId) {
        List<Case> cases = [
            SELECT Id, AccountId, Account.Name, Account.Industry, Account.Owner.Name,
                   AssetId, EntitlementId,
                   ContactId, Contact.Name, Contact.Title, Contact.Phone, Contact.Email,
                   Contact.MailingCity, Contact.MailingStreet
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            throw new AuraHandledException('Case not found: ' + caseId);
        }
        return cases[0];
    }

    private static ProfileInfo buildProfile(Case current) {
        ProfileInfo p = new ProfileInfo();
        p.industry = current.Account?.Industry;
        p.ownerName = current.Account?.Owner?.Name;
        p.contactName = current.Contact?.Name;
        p.contactTitle = current.Contact?.Title;
        p.contactPhone = current.Contact?.Phone;
        p.contactEmail = current.Contact?.Email;
        String street = current.Contact?.MailingStreet;
        String city = current.Contact?.MailingCity;
        if (String.isNotBlank(city) || String.isNotBlank(street)) {
            p.contactAddress = (city == null ? '' : city) +
                (String.isNotBlank(city) && String.isNotBlank(street) ? ' ' : '') +
                (street == null ? '' : street);
        }

        p.contactInitial = '';
        if (String.isNotBlank(p.contactName)) {
            p.contactInitial = p.contactName.substring(0, 1);
        }
        p.contactRole = p.contactTitle;
        if (current.Account?.Name != null) {
            p.contactRole = (p.contactRole == null ? '' : p.contactRole + ' · ') + current.Account.Name;
        }

        return p;
    }

    /**
     * 고객사의 ServiceContract 전체를 반환하고, 현재 Case의 Entitlement가
     * 속한 계약을 하이라이트로 표시한다.
     */
    private static List<ContractInfo> buildContracts(Id accountId, Id currentEntitlementId) {
        Id highlightContractId = null;
        if (currentEntitlementId != null) {
            List<Entitlement> ents = [
                SELECT ServiceContractId
                FROM Entitlement
                WHERE Id = :currentEntitlementId
                WITH USER_MODE
                LIMIT 1
            ];
            if (!ents.isEmpty()) {
                highlightContractId = ents[0].ServiceContractId;
            }
        }

        List<ContractInfo> infos = new List<ContractInfo>();
        for (ServiceContract sc : [
            SELECT Id, Name, StartDate, EndDate, Status
            FROM ServiceContract
            WHERE AccountId = :accountId
            WITH USER_MODE
            ORDER BY EndDate DESC NULLS LAST
        ]) {
            ContractInfo info = new ContractInfo();
            info.id = sc.Id;
            info.name = sc.Name;
            info.startDate = sc.StartDate;
            info.endDate = sc.EndDate;
            info.status = sc.Status;
            info.isExpired = sc.EndDate != null && sc.EndDate < Date.today();
            info.isCurrent = highlightContractId != null && sc.Id == highlightContractId;
            infos.add(info);
        }
        return infos;
    }

    private static List<AssetInfo> buildAssets(Id accountId) {
        List<AssetInfo> infos = new List<AssetInfo>();
        for (Asset a : [
            SELECT Id, Name, Status, SerialNumber, InstallDate
            FROM Asset
            WHERE AccountId = :accountId
            WITH USER_MODE
            ORDER BY InstallDate DESC NULLS LAST
        ]) {
            AssetInfo info = new AssetInfo();
            info.id = a.Id;
            info.name = a.Name;
            info.status = a.Status;
            info.serialNumber = a.SerialNumber;
            info.installDate = a.InstallDate;
            infos.add(info);
        }
        return infos;
    }

    private static List<CaseInfo> buildPastCases(Id accountId, Id excludeCaseId) {
        List<CaseInfo> infos = new List<CaseInfo>();
        for (Case c : [
            SELECT Id, CaseNumber, Subject, Status, Priority, CreatedDate
            FROM Case
            WHERE AccountId = :accountId
              AND Id != :excludeCaseId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 20
        ]) {
            CaseInfo info = new CaseInfo();
            info.id = c.Id;
            info.caseNumber = c.CaseNumber;
            info.subject = c.Subject;
            info.status = c.Status;
            info.priority = c.Priority;
            info.createdDate = c.CreatedDate;
            infos.add(info);
        }
        return infos;
    }

    private static List<OpportunityInfo> buildOpportunities(Id accountId) {
        List<OpportunityInfo> infos = new List<OpportunityInfo>();
        for (Opportunity o : [
            SELECT Id, Name, StageName, Amount, CloseDate, IsWon, IsClosed
            FROM Opportunity
            WHERE AccountId = :accountId
            WITH USER_MODE
            ORDER BY CloseDate DESC
            LIMIT 20
        ]) {
            OpportunityInfo info = new OpportunityInfo();
            info.id = o.Id;
            info.name = o.Name;
            info.stageName = o.StageName;
            info.amount = o.Amount;
            info.closeDate = o.CloseDate;
            info.isWon = o.IsWon;
            info.isClosed = o.IsClosed;
            infos.add(info);
        }
        return infos;
    }

    // ─── DTOs ────────────────────────────────────────────────────────────

    public class Customer360 {
        @AuraEnabled public String accountName;
        @AuraEnabled public Id currentEntitlementId;
        @AuraEnabled public ProfileInfo profile;
        @AuraEnabled public List<ContractInfo> contracts = new List<ContractInfo>();
        @AuraEnabled public List<AssetInfo> assets = new List<AssetInfo>();
        @AuraEnabled public List<CaseInfo> pastCases = new List<CaseInfo>();
        @AuraEnabled public List<OpportunityInfo> opportunities = new List<OpportunityInfo>();
    }

    public class ProfileInfo {
        @AuraEnabled public String industry;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String contactName;
        @AuraEnabled public String contactInitial;
        @AuraEnabled public String contactRole;
        @AuraEnabled public String contactTitle;
        @AuraEnabled public String contactPhone;
        @AuraEnabled public String contactEmail;
        @AuraEnabled public String contactAddress;
    }

    public class ContractInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isExpired;
        @AuraEnabled public Boolean isCurrent;
    }

    public class AssetInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public Date installDate;
    }

    public class CaseInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public Datetime createdDate;
    }

    public class OpportunityInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String stageName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public Boolean isWon;
        @AuraEnabled public Boolean isClosed;
    }
}

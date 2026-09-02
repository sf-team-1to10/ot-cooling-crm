public with sharing class T5DispatchCandidatesController {

    @AuraEnabled(cacheable=true)
    public static CandidatesHeader getHeader(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id가 필요합니다.');
        }

        List<Case> cases = [
            SELECT Id, CaseNumber, Account.Name, Asset.Name,
                   Asset.Site_Location__c
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            throw new AuraHandledException('Case를 찾을 수 없습니다.');
        }
        Case c = cases[0];

        CandidatesHeader h = new CandidatesHeader();
        h.caseNumber = c.CaseNumber;
        h.accountName = c.Account?.Name;
        h.assetName = c.Asset?.Name;
        h.siteLocation = c.Asset?.Site_Location__c;

        List<ServiceAppointment> sas = [
            SELECT AppointmentNumber
            FROM ServiceAppointment
            WHERE ParentRecordId = :caseId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        h.appointmentNumber = sas.isEmpty() ? null : sas[0].AppointmentNumber;

        return h;
    }

    public class CandidatesHeader {
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String accountName;
        @AuraEnabled public String assetName;
        @AuraEnabled public String siteLocation;
        @AuraEnabled public String appointmentNumber;
    }
}

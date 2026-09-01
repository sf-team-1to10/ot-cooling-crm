/**
 * Controller for the "장애 신고" Experience Cloud portal screen (step 2).
 *
 * Creates a Case for one Asset the logged-in customer owns. The running user's
 * company (Account) and contact are resolved server-side from their own
 * Contact — never trusted from the client. After insert, the record is re-read
 * so the UI can show the Case number plus the values populated by org
 * automation (Account, Contact, and the warranty judgment).
 *
 * Fields this class WRITES on Case:
 *   - AssetId              (Lookup(Asset))      — selected asset
 *   - Symptom_Category__c  (Picklist)           — 증상 분류
 *   - Impact_Level__c      (Picklist)           — 영향 등급
 *   - Reported_Symptom__c  (Long Text Area)     — 고객 진술 원문
 *   - AccountId            (Lookup(Account))    — 로그인 고객사 (화면이 채움)
 *   - ContactId            (Lookup(Contact))    — 로그인 담당자 (화면이 채움)
 *   - Origin               (Picklist)           — 신고 경로, 항상 'Web'
 *   - Subject              (Text)               — 증상 분류를 제목으로 사용
 *
 * Fields this class NEVER writes (populated by the active before-save flow
 * Case_Assign_Entitlement_By_Impact and related automation on save):
 *   - Warranty_Decision__c, Coverage_Type__c, Billable__c
 *   - Warranty_End_Date_At_Request__c, Warranty_Judged_At__c
 *   - EntitlementId and any SLA/milestone fields
 */
public with sharing class OTCaseIntakeController {
    private static final String CASE_ORIGIN_WEB = 'Web';

    /**
     * Creates a portal Case for the given Asset and returns the saved record's
     * key fields (including automation-populated warranty results).
     *
     * @param request Wrapper carrying the selected Asset Id and the three
     *        user-entered field values.
     * @return CaseResult DTO with the new Case number and the re-read
     *         company / contact / warranty-judgment values.
     * @throws AuraHandledException When the input is invalid, the Asset does
     *         not belong to the running user's Account, or the insert fails.
     * @example
     * OTCaseIntakeController.CaseResult result =
     *     OTCaseIntakeController.createCase(request);
     */
    @AuraEnabled
    public static CaseResult createCase(CaseRequest request) {
        if (request == null || String.isBlank(request.assetId)) {
            throw newError('신고할 자산이 선택되지 않았습니다.');
        }
        if (String.isBlank(request.symptomCategory)) {
            throw newError('증상 분류를 선택해 주세요.');
        }
        if (String.isBlank(request.impactLevel)) {
            throw newError('영향 등급을 선택해 주세요.');
        }
        if (String.isBlank(request.reportedSymptom)) {
            throw newError('고객 진술을 입력해 주세요.');
        }

        try {
            Id accountId = resolveRunningUserAccountId();
            Id contactId = resolveRunningUserContactId();
            if (accountId == null || contactId == null) {
                throw newError('고객 계정 정보를 확인할 수 없습니다.');
            }

            Id assetId = (Id) request.assetId;
            assertAssetBelongsToAccount(assetId, accountId);

            Case newCase = new Case(
                AssetId = assetId,
                AccountId = accountId,
                ContactId = contactId,
                Origin = CASE_ORIGIN_WEB,
                Subject = request.symptomCategory,
                Symptom_Category__c = request.symptomCategory,
                Impact_Level__c = request.impactLevel,
                Reported_Symptom__c = request.reportedSymptom
            );

            // USER_MODE enforces the running user's CRUD/FLS on every field.
            Database.insert(newCase, AccessLevel.USER_MODE);

            return readBack(newCase.Id);
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            throw newError(
                '신고 저장에 실패했습니다: ' + e.getDmlMessage(0)
            );
        } catch (Exception e) {
            throw newError('신고를 저장하는 중 오류가 발생했습니다.');
        }
    }

    /**
     * Re-reads the saved Case so the UI can confirm what automation populated.
     *
     * @param caseId Id of the just-created Case.
     * @return CaseResult with the number, company, contact, and warranty
     *         judgment fields as stored after all save-time automation ran.
     */
    private static CaseResult readBack(Id caseId) {
        List<Case> cases = [
            SELECT CaseNumber, Account.Name, Contact.Name,
                   Warranty_Decision__c, Coverage_Type__c, Billable__c,
                   Warranty_End_Date_At_Request__c, Warranty_Judged_At__c
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            throw newError('생성된 신고를 다시 불러올 수 없습니다.');
        }
        return new CaseResult(cases[0]);
    }

    /**
     * Confirms the selected Asset belongs to the running user's Account so a
     * customer can never file a Case against another company's equipment.
     *
     * @param assetId Selected Asset Id.
     * @param accountId Running user's Account Id.
     * @throws AuraHandledException When the Asset is not on that Account.
     */
    private static void assertAssetBelongsToAccount(Id assetId, Id accountId) {
        List<Asset> assets = [
            SELECT Id
            FROM Asset
            WHERE Id = :assetId AND AccountId = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        if (assets.isEmpty()) {
            throw newError('선택한 자산에 대한 신고 권한이 없습니다.');
        }
    }

    /**
     * @return The running user's Account Id via their linked Contact, or null.
     */
    private static Id resolveRunningUserAccountId() {
        User user = getRunningUser();
        return (user == null || user.Contact == null)
            ? null
            : user.Contact.AccountId;
    }

    /**
     * @return The running user's Contact Id, or null when unlinked.
     */
    private static Id resolveRunningUserContactId() {
        User user = getRunningUser();
        return user == null ? null : user.ContactId;
    }

    /**
     * @return The running User with Contact context, or null if none found.
     */
    private static User getRunningUser() {
        List<User> users = [
            SELECT ContactId, Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH USER_MODE
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    /**
     * @param message User-facing message.
     * @return An AuraHandledException whose message is safe to display.
     */
    private static AuraHandledException newError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }

    /**
     * Input wrapper for the three user-entered values plus the selected Asset.
     */
    public class CaseRequest {
        @AuraEnabled
        public String assetId { get; set; }
        @AuraEnabled
        public String symptomCategory { get; set; }
        @AuraEnabled
        public String impactLevel { get; set; }
        @AuraEnabled
        public String reportedSymptom { get; set; }
    }

    /**
     * Read-only projection returned after save. Warranty fields reflect values
     * set by org automation, not by this class.
     */
    public class CaseResult {
        @AuraEnabled
        public String caseNumber { get; set; }
        @AuraEnabled
        public String accountName { get; set; }
        @AuraEnabled
        public String contactName { get; set; }
        @AuraEnabled
        public String warrantyDecision { get; set; }
        @AuraEnabled
        public String coverageType { get; set; }
        @AuraEnabled
        public Boolean billable { get; set; }
        @AuraEnabled
        public Date warrantyEndDateAtRequest { get; set; }
        @AuraEnabled
        public Datetime warrantyJudgedAt { get; set; }

        /**
         * @param record Case re-read after all save-time automation ran.
         */
        public CaseResult(Case record) {
            this.caseNumber = record.CaseNumber;
            this.accountName = record.Account == null
                ? null
                : record.Account.Name;
            this.contactName = record.Contact == null
                ? null
                : record.Contact.Name;
            this.warrantyDecision = record.Warranty_Decision__c;
            this.coverageType = record.Coverage_Type__c;
            this.billable = record.Billable__c;
            this.warrantyEndDateAtRequest = record.Warranty_End_Date_At_Request__c;
            this.warrantyJudgedAt = record.Warranty_Judged_At__c;
        }
    }
}

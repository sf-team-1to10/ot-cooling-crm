/**
 * Read-only controller for the "내 자산" Experience Cloud portal screen.
 *
 * Returns only the Assets that belong to the logged-in community user's own
 * Account. Scoping is derived from the running user's Contact.AccountId — never
 * from a client-supplied Account Id — so records from other Accounts can never
 * be returned. FLS is enforced with Security.stripInaccessible before the data
 * leaves the server.
 */
public with sharing class OTMyAssetsController {
    @TestVisible
    private static final Set<String> ASSET_FIELDS = new Set<String>{
        'Id',
        'Name',
        'SerialNumber',
        'Status',
        'InstallDate',
        'Product2.Name',
        'Applied_Revision__c',
        'Next_Inspection_Date__c',
        'Open_Items_Summary__c'
    };

    /**
     * Returns the current portal user's Assets, scoped to their own Account.
     *
     * @return List of AssetView DTOs for the running user's Account; empty list
     *         when the user has no Contact/Account or owns no Assets.
     * @example
     * List<OTMyAssetsController.AssetView> myAssets =
     *     OTMyAssetsController.getMyAssets();
     */
    @AuraEnabled(cacheable=true)
    public static List<AssetView> getMyAssets() {
        try {
            Id accountId = resolveRunningUserAccountId();
            if (accountId == null) {
                return new List<AssetView>();
            }

            List<Asset> assets = [
                SELECT Id, Name, SerialNumber, Status, InstallDate,
                       Product2.Name, Applied_Revision__c,
                       Next_Inspection_Date__c, Open_Items_Summary__c,
                       Latest_Trend_Flag__c
                FROM Asset
                WHERE AccountId = :accountId
                WITH USER_MODE
                ORDER BY Name
            ];

            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.READABLE,
                assets
            );
            List<Asset> accessibleAssets = (List<Asset>) decision.getRecords();

            List<AssetView> views = new List<AssetView>();
            for (Asset record : accessibleAssets) {
                views.add(new AssetView(record));
            }
            return views;
        } catch (Exception e) {
            throw new AuraHandledException(
                '자산 정보를 불러오는 중 오류가 발생했습니다.'
            );
        }
    }

    /**
     * Resolves the running user's Account Id from their linked Contact.
     *
     * @return The Account Id linked to the running user, or null if the user
     *         has no associated Contact/Account (e.g. an internal user).
     */
    private static Id resolveRunningUserAccountId() {
        List<User> users = [
            SELECT Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH USER_MODE
            LIMIT 1
        ];
        if (users.isEmpty() || users[0].Contact == null) {
            return null;
        }
        return users[0].Contact.AccountId;
    }

    /**
     * Serializable, read-only projection of an Asset for the portal UI.
     * Product name is flattened so the LWC can bind it in a datatable column.
     */
    public class AssetView {
        @AuraEnabled
        public Id assetId { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String serialNumber { get; set; }
        @AuraEnabled
        public String status { get; set; }
        @AuraEnabled
        public String productName { get; set; }
        @AuraEnabled
        public Date installDate { get; set; }
        @AuraEnabled
        public String appliedRevision { get; set; }
        @AuraEnabled
        public Date nextInspectionDate { get; set; }
        @AuraEnabled
        public Decimal openItemsSummary { get; set; }
        @AuraEnabled
        public String trendFlag { get; set; }

        /**
         * @param record Asset already filtered by stripInaccessible; any field
         *        the user cannot read is absent and reads back as null.
         */
        public AssetView(Asset record) {
            this.assetId = record.Id;
            this.name = record.Name;
            this.serialNumber = record.SerialNumber;
            this.status = record.Status;
            this.productName = record.Product2 == null
                ? null
                : record.Product2.Name;
            this.installDate = record.InstallDate;
            this.appliedRevision = record.Applied_Revision__c;
            this.nextInspectionDate = record.Next_Inspection_Date__c;
            this.openItemsSummary = record.Open_Items_Summary__c;
            this.trendFlag = record.Latest_Trend_Flag__c;
        }
    }
}

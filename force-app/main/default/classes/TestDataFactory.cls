/**
 * Shared test-only data factory. All methods run exclusively in test context
 * and create in-memory/DML records for assertions — no org seed data.
 */
@isTest
public class TestDataFactory {
    /**
     * @param name Account name.
     * @param doInsert Whether to insert the record.
     * @return The built (and optionally inserted) Account.
     */
    public static Account createAccount(String name, Boolean doInsert) {
        Account account = new Account(Name = name);
        if (doInsert) {
            insert account;
        }
        return account;
    }

    /**
     * @param accountId Parent Account Id.
     * @param lastName Contact last name.
     * @param doInsert Whether to insert the record.
     * @return The built (and optionally inserted) Contact.
     */
    public static Contact createContact(
        Id accountId,
        String lastName,
        Boolean doInsert
    ) {
        Contact contact = new Contact(
            AccountId = accountId,
            LastName = lastName
        );
        if (doInsert) {
            insert contact;
        }
        return contact;
    }

    /**
     * @param accountId Owning Account Id.
     * @param count Number of Assets to build.
     * @param prefix Name/serial prefix for uniqueness.
     * @param doInsert Whether to insert the records.
     * @return The built (and optionally inserted) Assets.
     */
    public static List<Asset> createAssets(
        Id accountId,
        Integer count,
        String prefix,
        Boolean doInsert
    ) {
        List<Asset> assets = new List<Asset>();
        for (Integer i = 0; i < count; i++) {
            assets.add(
                new Asset(
                    Name = prefix + '-' + i,
                    AccountId = accountId,
                    SerialNumber = prefix + '-SN-' + i,
                    Status = 'Installed',
                    InstallDate = Date.newInstance(2027, 2, 18),
                    Applied_Revision__c = 'Rev.A',
                    Next_Inspection_Date__c = Date.newInstance(2027, 8, 18),
                    Open_Items_Summary__c = i
                )
            );
        }
        if (doInsert) {
            insert assets;
        }
        return assets;
    }

    /**
     * @param name Product name.
     * @param doInsert Whether to insert the record.
     * @return The built (and optionally inserted) Product2.
     */
    public static Product2 createProduct(String name, Boolean doInsert) {
        Product2 product = new Product2(Name = name, IsActive = true);
        if (doInsert) {
            insert product;
        }
        return product;
    }

    /**
     * @param accountId Owning Account Id.
     * @param productId Product (model) the Asset represents.
     * @param name Asset name/serial prefix.
     * @param doInsert Whether to insert the record.
     * @return The built (and optionally inserted) Asset.
     */
    public static Asset createAssetForProduct(
        Id accountId,
        Id productId,
        String name,
        Boolean doInsert
    ) {
        Asset asset = new Asset(
            Name = name,
            AccountId = accountId,
            Product2Id = productId,
            SerialNumber = name + '-SN',
            Status = 'Installed',
            InstallDate = Date.newInstance(2027, 2, 18)
        );
        if (doInsert) {
            insert asset;
        }
        return asset;
    }

    /**
     * @param assetId Related Asset Id.
     * @param symptom Symptom_Category__c value.
     * @param status Case status ('New', 'Closed', ...).
     * @param cause Diagnosed_Cause__c value (nullable).
     * @param doInsert Whether to insert the record.
     * @return The built (and optionally inserted) Case.
     */
    public static Case createCase(
        Id assetId,
        String symptom,
        String status,
        String cause,
        Boolean doInsert
    ) {
        return createCase(assetId, symptom, status, cause, null, doInsert);
    }

    /**
     * @param assetId Related Asset Id.
     * @param symptom Symptom_Category__c value.
     * @param status Case status ('New', 'Closed', ...).
     * @param cause Diagnosed_Cause__c value (nullable).
     * @param resolutionHours Resolution_Hours__c value (nullable).
     * @param doInsert Whether to insert the record.
     * @return The built (and optionally inserted) Case.
     */
    public static Case createCase(
        Id assetId,
        String symptom,
        String status,
        String cause,
        Decimal resolutionHours,
        Boolean doInsert
    ) {
        Case caseRecord = new Case(
            Subject = 'Test ' + symptom + ' ' + status,
            Status = status,
            AssetId = assetId,
            Symptom_Category__c = symptom,
            Diagnosed_Cause__c = cause,
            Resolution_Hours__c = resolutionHours
        );
        if (doInsert) {
            insert caseRecord;
        }
        return caseRecord;
    }

    /**
     * Creates a Customer Community portal user linked to the given Contact.
     * Returns null if no Customer Community profile is available in the org.
     *
     * @param contactId Contact the community user is linked to.
     * @param uniqueKey Unique token for username/alias.
     * @return The inserted community User, or null if no portal profile exists.
     */
    public static User createCommunityUser(Id contactId, String uniqueKey) {
        List<Profile> profiles = [
            SELECT Id
            FROM Profile
            WHERE UserLicense.Name = 'Customer Community'
            LIMIT 1
        ];
        if (profiles.isEmpty()) {
            return null;
        }
        User communityUser = new User(
            ProfileId = profiles[0].Id,
            ContactId = contactId,
            Username = uniqueKey + '@ot-portal-test.example.com',
            Alias = 'otp' + uniqueKey.left(5),
            Email = uniqueKey + '@ot-portal-test.example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'PortalUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert communityUser;
        return communityUser;
    }

    /**
     * Creates an internal admin user that holds a UserRole, required as the
     * owner context when inserting portal (community) users.
     *
     * @param uniqueKey Unique token for username/alias.
     * @return The inserted admin User with a role.
     */
    public static User createAdminWithRole(String uniqueKey) {
        UserRole role = new UserRole(Name = 'OT Portal Test Role ' + uniqueKey);
        insert role;
        Profile adminProfile = [
            SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1
        ];
        User admin = new User(
            ProfileId = adminProfile.Id,
            UserRoleId = role.Id,
            Username = uniqueKey + '@ot-admin-test.example.com',
            Alias = 'ota' + uniqueKey.left(5),
            Email = uniqueKey + '@ot-admin-test.example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'AdminRole',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert admin;
        return admin;
    }
}
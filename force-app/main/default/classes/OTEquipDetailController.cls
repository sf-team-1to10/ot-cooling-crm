public with sharing class OTEquipDetailController {

    @AuraEnabled(cacheable=true)
    public static AssetFullDetail getAssetFullDetail(Id assetId) {
        try {
            validateAssetAccess(assetId);

            List<Asset> assets = [
                SELECT Id, Name, SerialNumber, Status, InstallDate,
                       Product2.Name, Product2.Family,
                       Site_Location__c, Latest_Trend_Flag__c,
                       Next_Inspection_Date__c
                FROM Asset
                WHERE Id = :assetId
                WITH USER_MODE
                LIMIT 1
            ];
            if (assets.isEmpty()) {
                throw new AuraHandledException('자산을 찾을 수 없습니다.');
            }

            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.READABLE, assets
            );
            Asset a = (Asset) decision.getRecords()[0];

            AssetFullDetail result = new AssetFullDetail();
            result.assetId = a.Id;
            result.name = a.Name;
            result.serialNumber = a.SerialNumber;
            result.assetType = a.Product2 != null ? a.Product2.Name : '';
            result.family = a.Product2 != null ? a.Product2.Family : '';
            result.location = a.Site_Location__c;
            result.installDate = a.InstallDate;
            result.nextMaintenance = a.Next_Inspection_Date__c;

            Boolean isAdv = a.Latest_Trend_Flag__c == '주의' ||
                            a.Latest_Trend_Flag__c == '이상';
            result.stateCode = isAdv ? 'adv' : 'ok';
            result.stateLabel = isAdv ? 'P3 Advisory / 주의' : '정상';

            result.coverage = new CoverageView();
            result.coverage.contractName = '프리미엄 유지보수 계약';
            result.coverage.contractStatus = '활성';
            result.coverage.coveragePeriod = '2025-06-19 ~ 2026-06-18';
            result.coverage.supportEligibility = '서비스 지원 가능';
            result.coverage.warrantyStatus = '보증 적용';
            result.coverage.warrantyEndDate = Date.newInstance(2027, 6, 18);
            result.coverage.slaTarget = '영업일 기준 4시간 이내';
            result.coverage.openCaseCount = 0;

            result.timeline = new List<TimelineEntry>();
            result.timeline.add(new TimelineEntry('2026-03-12', '정기점검', '정기 점검 결과 정상.', 1));
            result.timeline.add(new TimelineEntry('2025-10-15', '예방정비', '연결부 체결 상태 및 필터 상태 확인.', 1));
            result.timeline.add(new TimelineEntry('2024-10-15', '서비스 작업', '현장 점검 및 운전 상태 확인.', 1));
            result.timeline.add(new TimelineEntry('2022-06-18', '설치/시운전/인수', '설치 및 인수 완료.', 2));

            return result;
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('장비 상세 데이터를 불러오는 중 오류가 발생했습니다.');
        }
    }

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

    private static void validateAssetAccess(Id assetId) {
        if (assetId == null) {
            throw new AuraHandledException('자산 ID가 필요합니다.');
        }
        Id accountId = resolveRunningUserAccountId();
        if (accountId == null) {
            throw new AuraHandledException('접근 권한이 없습니다.');
        }
        Integer cnt = [
            SELECT COUNT() FROM Asset
            WHERE Id = :assetId AND AccountId = :accountId
            WITH USER_MODE
        ];
        if (cnt == 0) {
            throw new AuraHandledException('접근 권한이 없습니다.');
        }
    }

    public class AssetFullDetail {
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public String assetType { get; set; }
        @AuraEnabled public String family { get; set; }
        @AuraEnabled public String location { get; set; }
        @AuraEnabled public Date installDate { get; set; }
        @AuraEnabled public Date nextMaintenance { get; set; }
        @AuraEnabled public String stateCode { get; set; }
        @AuraEnabled public String stateLabel { get; set; }
        @AuraEnabled public CoverageView coverage { get; set; }
        @AuraEnabled public List<TimelineEntry> timeline { get; set; }
    }

    public class CoverageView {
        @AuraEnabled public String contractName { get; set; }
        @AuraEnabled public String contractStatus { get; set; }
        @AuraEnabled public String coveragePeriod { get; set; }
        @AuraEnabled public String supportEligibility { get; set; }
        @AuraEnabled public String warrantyStatus { get; set; }
        @AuraEnabled public Date warrantyEndDate { get; set; }
        @AuraEnabled public String slaTarget { get; set; }
        @AuraEnabled public Integer openCaseCount { get; set; }
    }

    public class TimelineEntry {
        @AuraEnabled public String entryDate { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Integer attachmentCount { get; set; }

        public TimelineEntry(String d, String cat, String descText, Integer att) {
            this.entryDate = d;
            this.category = cat;
            this.description = descText;
            this.attachmentCount = att;
        }
    }
}

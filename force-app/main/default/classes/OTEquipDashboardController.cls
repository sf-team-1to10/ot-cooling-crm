public with sharing class OTEquipDashboardController {

    @AuraEnabled(cacheable=true)
    public static DashboardData getEquipmentDashboard() {
        try {
            Id accountId = resolveRunningUserAccountId();
            if (accountId == null) {
                return new DashboardData();
            }

            List<Asset> assets = [
                SELECT Id, Name, SerialNumber, Status, InstallDate,
                       Product2.Name, Product2.Family,
                       Site_Location__c, Latest_Trend_Flag__c,
                       Next_Inspection_Date__c
                FROM Asset
                WHERE AccountId = :accountId
                WITH USER_MODE
                ORDER BY Latest_Trend_Flag__c DESC, Name ASC
            ];

            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.READABLE, assets
            );
            List<Asset> safe = (List<Asset>) decision.getRecords();

            DashboardData result = new DashboardData();
            Integer normalCount = 0;
            Integer advisoryCount = 0;
            Integer maintCount = 0;

            for (Asset a : safe) {
                EquipmentView v = new EquipmentView();
                v.assetId = a.Id;
                v.name = a.Name;
                v.serialNumber = a.SerialNumber;
                v.assetType = a.Product2 != null ? a.Product2.Name : '';
                v.family = a.Product2 != null ? a.Product2.Family : '';
                v.location = a.Site_Location__c;
                v.status = a.Status;
                v.installDate = a.InstallDate;

                Boolean isAdv = a.Latest_Trend_Flag__c == '주의' ||
                                a.Latest_Trend_Flag__c == '이상';
                v.stateCode = isAdv ? 'adv' : 'ok';
                v.stateLabel = isAdv ? 'P3 Advisory / 주의' : '정상';

                if (isAdv) { advisoryCount++; } else { normalCount++; }
                if (a.Next_Inspection_Date__c != null &&
                    a.Next_Inspection_Date__c <= Date.today().addDays(90)) {
                    maintCount++;
                }

                result.assets.add(v);
            }

            result.kpis = new KpiSummary();
            result.kpis.totalAssets = safe.size();
            result.kpis.normalCount = normalCount;
            result.kpis.advisoryCount = advisoryCount;
            result.kpis.maintenanceScheduledCount = maintCount;

            return result;
        } catch (Exception e) {
            throw new AuraHandledException('대시보드 데이터를 불러오는 중 오류가 발생했습니다.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static EquipmentDetailData getEquipmentDetail(Id assetId) {
        try {
            validateAssetAccess(assetId);

            List<Asset> assets = [
                SELECT Id, Name, SerialNumber, Status, InstallDate,
                       Product2.Name, Product2.Family,
                       Site_Location__c, Latest_Trend_Flag__c,
                       Next_Inspection_Date__c, Latest_Gauges_JSON__c,
                       Warranty_Type__c, Open_Items_Summary__c
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

            EquipmentDetailData result = new EquipmentDetailData();
            result.assetId = a.Id;
            result.name = a.Name;
            result.serialNumber = a.SerialNumber;
            result.assetType = a.Product2 != null ? a.Product2.Name : '';
            result.family = a.Product2 != null ? a.Product2.Family : '';
            result.location = a.Site_Location__c;
            result.installDate = a.InstallDate;
            result.nextMaintenance = a.Next_Inspection_Date__c;
            // T5-07 완료조건 "공개 필드 전부 표시" 중 보증/미조치건수가
            // 빠져있던 걸 여기서 채운다(2026-08-31, 사용자 요청으로 발견).
            result.warrantyType = a.Warranty_Type__c;
            result.openItemsSummary = a.Open_Items_Summary__c;
            // T5_Sync_Asset_Trend_Summary Flow가 WOLI 변경마다 갱신해두는
            // 게이지 스냅샷(OtTrendAlertCardController.GaugeView 목록을
            // 그대로 직렬화한 것) — LWC가 파싱해서 게이지·스파크라인·델타를
            // 그린다. 원본(WorkOrderLineItem)은 포털 라이선스로 직접 조회
            // 불가라 이 경로로 우회한다(T5SyncAssetTrendSummary 클래스 참고).
            result.gaugesJson = a.Latest_Gauges_JSON__c;

            Boolean isAdv = a.Latest_Trend_Flag__c == '주의' ||
                            a.Latest_Trend_Flag__c == '이상';
            result.stateCode = isAdv ? 'adv' : 'ok';
            result.stateLabel = isAdv ? 'P3 Advisory / 주의' : '정상';
            result.meta = (result.assetType != null ? result.assetType : '') +
                ' · ' + (result.family != null ? result.family : '') +
                ' · ' + (result.location != null ? result.location : '');
            result.imageUrl = resolveImageUrl(assetId);

            return result;
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('장비 상세 데이터를 불러오는 중 오류가 발생했습니다.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static LocationView getLocationInfo(Id assetId) {
        try {
            validateAssetAccess(assetId);
            Id accountId = resolveRunningUserAccountId();

            List<Account> accounts = [
                SELECT Name FROM Account WHERE Id = :accountId WITH USER_MODE LIMIT 1
            ];
            List<Asset> assets = [
                SELECT Site_Location__c FROM Asset WHERE Id = :assetId WITH USER_MODE LIMIT 1
            ];

            LocationView loc = new LocationView();
            loc.customerName = accounts.isEmpty() ? '' : accounts[0].Name;
            loc.siteName = '마이클라우드 데이터센터';
            loc.hall = 'Hall A';
            loc.assetRow = '';
            if (!assets.isEmpty() && assets[0].Site_Location__c != null) {
                loc.assetRow = assets[0].Site_Location__c;
            }
            return loc;
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('위치 정보를 불러오는 중 오류가 발생했습니다.');
        }
    }

    private static final Set<String> IMAGE_EXTS = new Set<String>{ 'png', 'jpg', 'jpeg', 'webp', 'gif' };

    private static String resolveImageUrl(Id assetId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersionId,
                   ContentDocument.FileExtension,
                   ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :assetId
            WITH USER_MODE
            ORDER BY ContentDocument.CreatedDate DESC
        ];
        if (links.isEmpty()) return null;
        // 1순위: '제품_' 접두사 갤러리 이미지 (가장 최신)
        for (ContentDocumentLink l : links) {
            if (l.ContentDocument == null) continue;
            String ext = (l.ContentDocument.FileExtension ?? '').toLowerCase();
            String title = (l.ContentDocument.Title ?? '').toLowerCase();
            if (!IMAGE_EXTS.contains(ext)) continue;
            if (title.startsWith('제품_') || title.startsWith('product_')) {
                return '/sfc/servlet.shepherd/version/download/' + l.ContentDocument.LatestPublishedVersionId;
            }
        }
        // 2순위: 제품·설치 키워드 포함 이미지
        for (ContentDocumentLink l : links) {
            if (l.ContentDocument == null) continue;
            String ext = (l.ContentDocument.FileExtension ?? '').toLowerCase();
            String title = (l.ContentDocument.Title ?? '').toLowerCase();
            if (!IMAGE_EXTS.contains(ext)) continue;
            if (title.contains('제품') || title.contains('설치') || title.contains('product') || title.contains('installed')) {
                return '/sfc/servlet.shepherd/version/download/' + l.ContentDocument.LatestPublishedVersionId;
            }
        }
        // 3순위: 첫 번째 이미지 파일
        for (ContentDocumentLink l : links) {
            if (l.ContentDocument == null) continue;
            String ext = (l.ContentDocument.FileExtension ?? '').toLowerCase();
            if (IMAGE_EXTS.contains(ext)) {
                return '/sfc/servlet.shepherd/version/download/' + l.ContentDocument.LatestPublishedVersionId;
            }
        }
        return null;
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

    public class DashboardData {
        @AuraEnabled public KpiSummary kpis { get; set; }
        @AuraEnabled public List<EquipmentView> assets { get; set; }
        public DashboardData() {
            this.kpis = new KpiSummary();
            this.assets = new List<EquipmentView>();
        }
    }

    public class KpiSummary {
        @AuraEnabled public Integer totalAssets { get; set; }
        @AuraEnabled public Integer normalCount { get; set; }
        @AuraEnabled public Integer advisoryCount { get; set; }
        @AuraEnabled public Integer maintenanceScheduledCount { get; set; }
        public KpiSummary() {
            totalAssets = 0; normalCount = 0; advisoryCount = 0; maintenanceScheduledCount = 0;
        }
    }

    public class EquipmentView {
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public String assetType { get; set; }
        @AuraEnabled public String family { get; set; }
        @AuraEnabled public String location { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date installDate { get; set; }
        @AuraEnabled public String stateCode { get; set; }
        @AuraEnabled public String stateLabel { get; set; }
        @AuraEnabled public String imageUrl { get; set; }
        @AuraEnabled public String imageNote { get; set; }
    }

    public class EquipmentDetailData {
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
        @AuraEnabled public String meta { get; set; }
        @AuraEnabled public String warrantyType { get; set; }
        @AuraEnabled public Decimal openItemsSummary { get; set; }
        @AuraEnabled public String gaugesJson { get; set; }
        @AuraEnabled public String imageUrl { get; set; }
    }

    public class LocationView {
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String siteName { get; set; }
        @AuraEnabled public String hall { get; set; }
        @AuraEnabled public String assetRow { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<AlertView> getAlerts(Id assetId) {
        validateAssetAccess(assetId);
        List<Customer_Alert__c> rows = [
            SELECT Priority__c, Status__c, Message__c, Started_At__c
            FROM Customer_Alert__c
            WHERE Asset__c = :assetId
            WITH USER_MODE
            ORDER BY Started_At__c DESC
            LIMIT 10
        ];
        List<AlertView> result = new List<AlertView>();
        for (Customer_Alert__c r : rows) {
            AlertView v = new AlertView();
            v.priority = r.Priority__c;
            v.status = r.Status__c;
            v.message = r.Message__c;
            v.startedAt = r.Started_At__c;
            v.tagClass = (r.Priority__c == 'P1' || r.Priority__c == 'P2') ? 'tag crit' : 'tag warn';
            v.tagLabel = r.Priority__c != null ? r.Priority__c : '알람';
            result.add(v);
        }
        return result;
    }

    public class AlertView {
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Datetime startedAt { get; set; }
        @AuraEnabled public String tagClass { get; set; }
        @AuraEnabled public String tagLabel { get; set; }
    }
}
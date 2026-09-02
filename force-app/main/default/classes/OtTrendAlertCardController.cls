/**
 * Read-only controller for the "otTrendAlertCard" portal Trend widget (T5-07).
 *
 * Returns a single Asset's status badge, latest Trend_Flag__c judgement,
 * warranty/inspection summary, a representative image (if attached), and
 * one gauge view per currently-abnormal measurement item (with a short
 * sparkline + before/after delta each).
 *
 * 계정 스코핑 있음(2026-08-30 최종 결정): 처음엔 로그인 없는 Guest 공개로 가려
 * 했으나, WorkOrderLineItem이 Guest User License가 지원하는 객체 목록에 아예
 * 없다는 플랫폼 제약을 만나 철회했다(Object Permissions를 아무리 줘도
 * "bad value for restricted picklist field" — 권한 문제가 아니라 라이선스
 * 하드 제약). `without sharing`으로 우회하는 방법도 검토했으나, 이 컨트롤러가
 * 노출하는 다른 객체까지 전부 시스템 컨텍스트로 뚫려버려 Guest 우회 패턴이
 * 계속 쌓이는 문제가 있어 기각 — 대신 원래 계획대로 Customer Community User
 * 로그인 기반으로 되돌아간다(OTMyAssetsController와 동일 패턴). 호출자는
 * 자신의 Contact.AccountId에 속한 Asset만 조회 가능 — 서버에서 매번
 * 재확인하며 클라이언트 입력을 신뢰하지 않는다.
 */
public with sharing class OtTrendAlertCardController {
    @TestVisible
    private static final Set<String> ATTENTION_TREND_FLAGS = new Set<String>{
        '주의',
        '이상'
    };

    /** How many recent readings (per measurement item) to include in the sparkline. */
    private static final Integer SPARKLINE_POINTS = 8;

    /** How many recent WOLI rows (across all measurement items) to scan when
     *  building gauges — large enough to cover SPARKLINE_POINTS per item for
     *  a handful of distinct items without an unbounded query. */
    private static final Integer READING_SCAN_LIMIT = 200;

    /**
     * Whether the "Agent 상담" entry point should render (T5-11).
     * Reads T5_Feature_Flags__mdt.Service_Agent_Enabled__c — an admin can
     * flip this Custom Metadata value without a code deploy to hide the
     * button instantly if the Agent (T5-08) or its channel misbehaves.
     * Custom Metadata Type field reads need no explicit FLS (compiled into
     * the package like a Custom Label), so no extra Permission Set grant.
     *
     * @return True when the flag record's checkbox is checked; false if the
     *         flag or record is missing so the button fails closed (RG-10 —
     *         the plain fault form stays the always-available fallback).
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isServiceAgentEnabled() {
        T5_Feature_Flags__mdt flags = T5_Feature_Flags__mdt.getInstance('Default');
        return flags != null && flags.Service_Agent_Enabled__c == true;
    }

    /**
     * Returns Trend/status view data for one Asset owned by the running
     * user's Account.
     *
     * @param assetId Asset to look up; must belong to the caller's own Account.
     * @return TrendView, or null when the Asset doesn't exist, isn't visible
     *         to the caller, or the caller has no linked Account.
     */
    @AuraEnabled(cacheable=true)
    public static TrendView getAssetTrendInfo(Id assetId) {
        try {
            Id accountId = resolveRunningUserAccountId();
            if (accountId == null || assetId == null) {
                return null;
            }

            List<Asset> assets = [
                SELECT Id, Name, Status, InstallDate, Product2.Name,
                       Applied_Revision__c, Next_Inspection_Date__c,
                       Open_Items_Summary__c, Latest_Trend_Flag__c,
                       Latest_Gauges_JSON__c
                FROM Asset
                WHERE Id = :assetId AND AccountId = :accountId
                WITH USER_MODE
                LIMIT 1
            ];
            if (assets.isEmpty()) {
                return null;
            }

            SObjectAccessDecision assetDecision = Security.stripInaccessible(
                AccessType.READABLE,
                assets
            );
            List<Asset> accessibleAssets = (List<Asset>) assetDecision.getRecords();
            Asset record = accessibleAssets[0];

            // 포털은 WorkOrderLineItem을 직접 조회하지 않는다(2026-08-30 확인 —
            // 이 org에서 WorkOrderLineItem은 관리자를 제외한 어떤 Profile/
            // Permission Set에도 명시적 Object 권한을 못 준다, Guest·Customer
            // Community 양쪽 다 "restricted picklist" 에러로 확인). 대신
            // T5_Sync_Asset_Trend_Summary Flow가 WorkOrderLineItem 저장 시마다
            // Asset의 이 두 필드로 미리 복사해둔 요약값을 읽기만 한다. 내부
            // 사용자용(T5-21 등)은 이 제약이 없으므로 resolveGauges/
            // resolveLatestTrendFlag를 계속 직접 호출하면 된다(아래 public
            // 메서드로 남겨둔 이유).
            String latestTrendFlag = record.Latest_Trend_Flag__c;
            List<GaugeView> gauges = String.isBlank(record.Latest_Gauges_JSON__c)
                ? new List<GaugeView>()
                : (List<GaugeView>) JSON.deserialize(
                    record.Latest_Gauges_JSON__c,
                    List<GaugeView>.class
                );
            String imageUrl = resolveImageUrl(assetId);

            return new TrendView(record, latestTrendFlag, imageUrl, gauges);
        } catch (Exception e) {
            throw new AuraHandledException(
                '자산 추이 정보를 불러오는 중 오류가 발생했습니다.'
            );
        }
    }

    /**
     * 자산의 종합 추세 상태. 측정 항목별 최신 판정을 종합해, 하나라도
     * 이상이면 '이상', 주의가 있으면 '주의', 모두 정상이면 '정상',
     * 측정 이력이 없으면 null을 돌려준다.
     *
     * 왜 단일 최신행이 아닌가: 항목마다 마지막 측정 시점(WorkOrder.StartDate)이
     * 달라, 전 항목 통틀어 "가장 최근 1건"만 보면 그 시점에 정상인 다른 항목이
     * 유량·차압의 주의를 덮어버린다. 자산 뱃지는 "어느 항목이든 비정상이면
     * 비정상"이어야 하므로 항목별 최신을 종합한다. 비정상 항목 판정은
     * resolveGauges와 같은 소스를 재사용한다(중복 로직 없음).
     *
     * public: also called by T5SyncAssetTrendSummary (internal system
     * context, no license restriction) to denormalize this onto Asset for
     * the portal, which cannot query WorkOrderLineItem directly.
     */
    public static String resolveLatestTrendFlag(Id assetId) {
        Boolean hasIsang = false;
        Boolean hasJuui = false;
        for (GaugeView g : resolveGauges(assetId)) {
            if (g.trendFlag == '이상') {
                hasIsang = true;
            } else if (g.trendFlag == '주의') {
                hasJuui = true;
            }
        }
        if (hasIsang) {
            return '이상';
        }
        if (hasJuui) {
            return '주의';
        }
        // 비정상 항목 없음 — 측정 이력이 있으면 '정상', 아예 없으면 null.
        Integer readingCount = [
            SELECT COUNT()
            FROM WorkOrderLineItem
            WHERE WorkOrder.AssetId = :assetId
            WITH USER_MODE
        ];
        return readingCount > 0 ? '정상' : null;
    }

    /**
     * Builds one GaugeView per measurement item that is *currently* 주의/이상
     * (T5-시각화_실시간알림_구조정리.md 5장 — 고객용은 비정상 항목만, 정상 항목은
     * 숨긴다). Scans the most recent READING_SCAN_LIMIT rows across all items,
     * groups them by Measurement_Item_Code__c in memory (rows arrive newest
     * first per item within that ordering), and uses the newest row per group
     * to decide inclusion + current value, and up to SPARKLINE_POINTS oldest→
     * newest values for the sparkline.
     *
     * Reads WOLI_Trend_Flag_Evaluate's Trend_Flag__c and
     * WOLI_Baseline_Prior_Compare's Delta_From_Previous__c — both T4-owned
     * Flows, read-only here, no new judgement logic.
     *
     * public: also called by T5SyncAssetTrendSummary — see resolveLatestTrendFlag.
     */
    public static List<GaugeView> resolveGauges(Id assetId) {
        List<WorkOrderLineItem> readings = [
            SELECT Id, Measurement_Item_Code__c, Measured_Value__c,
                   Trend_Flag__c, Delta_From_Previous__c, CreatedDate
            FROM WorkOrderLineItem
            WHERE WorkOrder.AssetId = :assetId
              AND Measurement_Item_Code__c != null
              AND Measured_Value__c != null
            WITH USER_MODE
            ORDER BY WorkOrder.StartDate DESC NULLS LAST, CreatedDate DESC
            LIMIT :READING_SCAN_LIMIT
        ];

        SObjectAccessDecision readingDecision = Security.stripInaccessible(
            AccessType.READABLE,
            readings
        );
        List<WorkOrderLineItem> accessibleReadings =
            (List<WorkOrderLineItem>) readingDecision.getRecords();

        // Group by measurement item, preserving newest-first order within each group.
        Map<String, List<WorkOrderLineItem>> byItem = new Map<String, List<WorkOrderLineItem>>();
        for (WorkOrderLineItem woli : accessibleReadings) {
            String itemCode = woli.Measurement_Item_Code__c;
            if (!byItem.containsKey(itemCode)) {
                byItem.put(itemCode, new List<WorkOrderLineItem>());
            }
            byItem.get(itemCode).add(woli);
        }

        List<GaugeView> gauges = new List<GaugeView>();
        for (String itemCode : byItem.keySet()) {
            List<WorkOrderLineItem> itemReadings = byItem.get(itemCode);
            WorkOrderLineItem latest = itemReadings[0];

            if (!ATTENTION_TREND_FLAGS.contains(latest.Trend_Flag__c)) {
                continue; // only surface currently-abnormal items to the customer
            }

            List<Decimal> sparkline = new List<Decimal>();
            Integer count = Math.min(SPARKLINE_POINTS, itemReadings.size());
            for (Integer i = count - 1; i >= 0; i--) {
                sparkline.add(itemReadings[i].Measured_Value__c);
            }

            Decimal previousValue = (latest.Delta_From_Previous__c != null)
                ? latest.Measured_Value__c - latest.Delta_From_Previous__c
                : null;

            gauges.add(new GaugeView(
                itemCode,
                latest.Trend_Flag__c,
                latest.Measured_Value__c,
                previousValue,
                latest.Delta_From_Previous__c,
                sparkline
            ));
        }
        return gauges;
    }

    /**
     * Looks up the first file attached to the Asset (ContentDocumentLink →
     * ContentVersion), if any. Assets are not required to have an image.
     *
     * NOTE (확인 필요): this download URL pattern works reliably inside
     * standard Lightning Experience. Whether it renders in an Experience
     * Cloud portal context depends on site sharing settings — verify this
     * at step 8 (독립 페이지 육안 테스트) before trusting it in the real
     * portal. If it doesn't render, the fallback is a public Content
     * Distribution link generated per-file.
     */
    private static String resolveImageUrl(Id assetId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :assetId
            WITH USER_MODE
            LIMIT 1
        ];
        if (links.isEmpty() || links[0].ContentDocument == null) {
            return null;
        }
        Id versionId = links[0].ContentDocument.LatestPublishedVersionId;
        return '/sfc/servlet.shepherd/version/download/' + versionId;
    }

    /**
     * Resolves the running user's Account Id from their linked Contact.
     * Duplicated from OTMyAssetsController rather than shared, matching this
     * codebase's existing per-controller pattern.
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

    /** Serializable, read-only projection of an Asset for the Trend card UI. */
    public class TrendView {
        @AuraEnabled
        public Id assetId { get; set; }
        @AuraEnabled
        public String name { get; set; }
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
        @AuraEnabled
        public Boolean needsAttention { get; set; }
        @AuraEnabled
        public String imageUrl { get; set; }
        @AuraEnabled
        public List<GaugeView> gauges { get; set; }

        /**
         * @param record Asset already filtered by stripInaccessible; any
         *        field the user cannot read is absent and reads back as null.
         * @param trendFlag Latest WorkOrderLineItem.Trend_Flag__c value
         *        (정상/주의/이상), or null if no checks exist yet.
         * @param imageUrl First attached file's download URL, or null.
         * @param gauges One entry per currently-abnormal measurement item.
         */
        public TrendView(Asset record, String trendFlag, String imageUrl, List<GaugeView> gauges) {
            this.assetId = record.Id;
            this.name = record.Name;
            this.status = record.Status;
            this.productName = record.Product2 == null
                ? null
                : record.Product2.Name;
            this.installDate = record.InstallDate;
            this.appliedRevision = record.Applied_Revision__c;
            this.nextInspectionDate = record.Next_Inspection_Date__c;
            this.openItemsSummary = record.Open_Items_Summary__c;
            this.trendFlag = trendFlag;
            this.needsAttention = ATTENTION_TREND_FLAGS.contains(trendFlag);
            this.imageUrl = imageUrl;
            this.gauges = gauges;
        }
    }

    /** One gauge's worth of data: current state + short recent history. */
    public class GaugeView {
        @AuraEnabled
        public String measurementItemCode { get; set; }
        @AuraEnabled
        public String trendFlag { get; set; }
        @AuraEnabled
        public Decimal currentValue { get; set; }
        @AuraEnabled
        public Decimal previousValue { get; set; }
        @AuraEnabled
        public Decimal deltaFromPrevious { get; set; }
        @AuraEnabled
        public List<Decimal> sparklineValues { get; set; }

        public GaugeView(
            String measurementItemCode,
            String trendFlag,
            Decimal currentValue,
            Decimal previousValue,
            Decimal deltaFromPrevious,
            List<Decimal> sparklineValues
        ) {
            this.measurementItemCode = measurementItemCode;
            this.trendFlag = trendFlag;
            this.currentValue = currentValue;
            this.previousValue = previousValue;
            this.deltaFromPrevious = deltaFromPrevious;
            this.sparklineValues = sparklineValues;
        }
    }
}
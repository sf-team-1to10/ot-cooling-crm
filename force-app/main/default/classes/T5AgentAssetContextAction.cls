public without sharing class T5AgentAssetContextAction {

    @InvocableMethod(
        label='Get Asset Context for Agent'
        description='포털에서 채팅을 시작한 자산의 실시간 상태(모델·시리얼·게이지 추세·보증)를 조회한다. T5-23 — 고객이 장비를 말하기 전에 Agent가 컨텍스트를 먼저 파악하기 위한 액션.'
    )
    public static List<AssetContextOutput> getContext(List<AssetContextInput> inputs) {
        List<AssetContextOutput> results = new List<AssetContextOutput>();
        for (AssetContextInput inp : inputs) {
            results.add(execute(inp));
        }
        return results;
    }

    private static AssetContextOutput execute(AssetContextInput inp) {
        AssetContextOutput out = new AssetContextOutput();

        // T5-23: Agent Script의 linked variable은 @MessagingSession.Id/
        // MessagingEndUserId/EndUserLanguage만 지원하고 커스텀 필드는 직접
        // 못 읽는다(공식 문서 확인, 2026-08-31). 그래서 이 Apex가 RoutableId
        // (=MessagingSession.Id, 이미 linked variable로 존재)를 받아서
        // Hidden Pre-Chat Field로 채워진 MessagingSession.Asset_Id__c를
        // 직접 SOQL로 조회한다 — 제약 없이 커스텀 필드를 읽는 우회로.
        Id assetId = resolveAssetIdFromSession(inp.sessionId);
        if (assetId == null) {
            out.found = false;
            return out;
        }

        try {
            // T5-07의 OTEquipDashboardController는 validateAssetAccess()가
            // "실행 유저의 Contact.AccountId == 자산 소유 Account"를 요구해서
            // 포털 고객 유저 전용이다 — Agent 실행 유저(ot_service_agent@…ext)는
            // 매칭되는 Contact가 없어 항상 거부당한다(2026-08-31 실측). 그래서
            // 같은 필드셋을 이 클래스에서 독립적으로 조회한다. 보안 경계는
            // Agent용 Permission Set의 필드/오브젝트 FLS로 대체.
            List<Asset> assets = [
                SELECT Id, Name, SerialNumber, Product2.Name, Product2.Family,
                       Site_Location__c, Latest_Trend_Flag__c,
                       Warranty_Type__c, Open_Items_Summary__c, Latest_Gauges_JSON__c
                FROM Asset
                WHERE Id = :assetId
                WITH USER_MODE
                LIMIT 1
            ];
            if (assets.isEmpty()) {
                out.found = false;
                return out;
            }
            Asset a = assets[0];
            Boolean isAdv = a.Latest_Trend_Flag__c == '주의' || a.Latest_Trend_Flag__c == '이상';

            out.found = true;
            out.assetName = a.Name;
            out.serialNumber = a.SerialNumber;
            out.assetType = a.Product2 != null ? a.Product2.Name : '';
            out.stateLabel = isAdv ? 'P3 Advisory / 주의' : '정상';
            out.warrantyType = a.Warranty_Type__c;
            out.openItemsSummary = a.Open_Items_Summary__c;

            if (String.isNotBlank(a.Latest_Gauges_JSON__c)) {
                List<Object> gauges = (List<Object>) JSON.deserializeUntyped(a.Latest_Gauges_JSON__c);
                Map<String, Object> primary = pickPrimaryGauge(gauges);
                if (primary != null) {
                    out.measurementItemCode = (String) primary.get('measurementItemCode');
                    out.trendFlag = (String) primary.get('trendFlag');
                    Object cur = primary.get('currentValue');
                    Object prev = primary.get('previousValue');
                    out.currentValue = cur != null ? String.valueOf(cur) : null;
                    out.previousValue = prev != null ? String.valueOf(prev) : null;
                }
            }
        } catch (Exception e) {
            out.found = false;
            out.errorMessage = e.getMessage();
        }
        return out;
    }

    private static Id resolveAssetIdFromSession(String sessionIdStr) {
        if (String.isBlank(sessionIdStr)) {
            return null;
        }
        try {
            Id sessionId = Id.valueOf(sessionIdStr);
            List<MessagingSession> sessions = [
                SELECT Asset_Id__c FROM MessagingSession WHERE Id = :sessionId LIMIT 1
            ];
            if (sessions.isEmpty() || String.isBlank(sessions[0].Asset_Id__c)) {
                return null;
            }
            Id assetId = Id.valueOf(sessions[0].Asset_Id__c);
            return assetId.getSObjectType() == Asset.SObjectType ? assetId : null;
        } catch (Exception e) {
            return null;
        }
    }

    // 여러 게이지 중 이상 추세(trendFlag가 정상이 아닌) 항목을 우선, 없으면 첫 항목.
    private static Map<String, Object> pickPrimaryGauge(List<Object> gauges) {
        if (gauges == null || gauges.isEmpty()) {
            return null;
        }
        for (Object g : gauges) {
            Map<String, Object> gm = (Map<String, Object>) g;
            String flag = (String) gm.get('trendFlag');
            if (String.isNotBlank(flag) && flag != 'Normal' && flag != '정상') {
                return gm;
            }
        }
        return (Map<String, Object>) gauges[0];
    }

    public class AssetContextInput {
        @InvocableVariable(label='Session Id' description='현재 MessagingSession Id(RoutableId). 이 값으로 Hidden Pre-Chat Field에 저장된 자산 Id를 역조회한다.' required=true)
        public String sessionId;
    }

    public class AssetContextOutput {
        @InvocableVariable(label='Found') public Boolean found;
        @InvocableVariable(label='Asset Name') public String assetName;
        @InvocableVariable(label='Serial Number') public String serialNumber;
        @InvocableVariable(label='Asset Type') public String assetType;
        @InvocableVariable(label='State Label') public String stateLabel;
        @InvocableVariable(label='Warranty Type') public String warrantyType;
        @InvocableVariable(label='Next Maintenance') public String nextMaintenance;
        @InvocableVariable(label='Open Items Summary') public Decimal openItemsSummary;
        @InvocableVariable(label='Measurement Item Code') public String measurementItemCode;
        @InvocableVariable(label='Trend Flag') public String trendFlag;
        @InvocableVariable(label='Current Value') public String currentValue;
        @InvocableVariable(label='Previous Value') public String previousValue;
        @InvocableVariable(label='Error Message') public String errorMessage;
    }
}

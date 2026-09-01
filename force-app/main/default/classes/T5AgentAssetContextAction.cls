public without sharing class T5AgentAssetContextAction {

    @InvocableMethod(
        label='Get Asset Context for Agent'
        description='포털에서 채팅을 시작한 자산의 실시간 상태(모델·시리얼·게이지 추세·보증)를 조회한다. 게이지는 Asset 스냅샷이 아니라 IoT가 흘려보낸 WorkOrderLineItem 측정 이력을 실시간으로 읽는다(T5-06 파이프라인·T5-07 포털 카드와 동일 소스).'
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

        Id assetId = resolveAssetIdForAgent(inp.sessionId);
        if (assetId == null) {
            out.found = false;
            out.errorMessage = 'sessionId=' + inp.sessionId + ' → assetId=null';
            return out;
        }

        try {
            // T5-07 OtTrendAlertCardController.getAssetTrendInfo와 같은 필드셋.
            // Agent 실행 유저는 포털 고객이 아니라 통합 계정이라 계정 스코핑
            // (AccountId 매칭)은 걸지 않는다 — 보안 경계는 Agent Permission Set의
            // 오브젝트/FLS로 대체(작업기록 T5-08 5절 C 참조).
            List<Asset> assets = [
                SELECT Id, Name, SerialNumber, Product2.Name, Product2.Family,
                       Site_Location__c, Warranty_Type__c, Open_Items_Summary__c
                FROM Asset
                WHERE Id = :assetId
                LIMIT 1
            ];
            if (assets.isEmpty()) {
                out.found = false;
                return out;
            }
            Asset a = assets[0];

            List<GaugeInfo> gauges = resolveGaugesForAgent(assetId);
            GaugeInfo primary = pickPrimary(gauges);
            Boolean anyAbnormal = false;
            for (GaugeInfo g : gauges) {
                if (g.abnormal) { anyAbnormal = true; break; }
            }

            out.found = true;
            out.assetName = a.Name;
            out.serialNumber = a.SerialNumber;
            out.assetType = a.Product2 != null ? a.Product2.Name : '';
            out.stateLabel = anyAbnormal ? 'P3 Advisory / 주의' : '정상';
            out.warrantyType = a.Warranty_Type__c;
            out.openItemsSummary = a.Open_Items_Summary__c;
            out.gaugesSummary = formatGaugesSummary(gauges);
            out.maintenanceHistory = formatMaintenanceHistory(assetId);

            if (primary != null) {
                out.measurementItemCode = primary.measurementItemCode;
                out.trendFlag = primary.trendFlag;
                out.currentValue = primary.currentValue != null ? String.valueOf(primary.currentValue) : null;
                out.previousValue = primary.previousValue != null ? String.valueOf(primary.previousValue) : null;
                out.baselineRange = formatBaselineRange(primary);
                out.advisoryDuration = primary.abnormal ? formatDuration(primary.streakStart) : null;
            }
        } catch (Exception e) {
            out.found = false;
            out.errorMessage = e.getMessage();
        }
        return out;
    }

    /**
     * IoT가 흘려보낸 측정 이력(WorkOrderLineItem)을 측정 항목별로 실시간 조회한다.
     * T5-07 OtTrendAlertCardController.resolveGauges와 같은 조회·그룹핑 방식이지만,
     * Agent는 고객 화면과 달리 정상 항목도 알아야 하므로(예: "공급수 온도는 정상")
     * 비정상 항목만 거르지 않고 전 항목을 돌려준다. 판정 로직은 없다 —
     * WOLI_Trend_Flag_Evaluate(T4 소유)가 이미 채워둔 Trend_Flag__c를 읽기만 한다.
     */
    public static List<GaugeInfo> resolveGaugesForAgent(Id assetId) {
        // WorkOrder.StartDate는 측정 회차마다 증가하므로 "최신 측정"을 안정적으로
        // 잡는 1차 기준으로 쓴다(같은 초에 여러 건이 insert돼 CreatedDate만으로는
        // 타이가 나는 것을 방지). StartDate가 없으면 CreatedDate로 폴백한다.
        List<WorkOrderLineItem> readings = [
            SELECT Measurement_Item_Code__c, Measured_Value__c, Baseline_Value__c,
                   Delta_From_Previous__c, Previous_Measured_Value__c,
                   Trend_Flag__c, CreatedDate, WorkOrder.StartDate
            FROM WorkOrderLineItem
            WHERE WorkOrder.AssetId = :assetId
              AND Measurement_Item_Code__c != null
              AND Measured_Value__c != null
            ORDER BY WorkOrder.StartDate DESC NULLS LAST, CreatedDate DESC
            LIMIT 200
        ];

        // 측정 항목별로 최신순 유지하며 그룹핑.
        Map<String, List<WorkOrderLineItem>> byItem = new Map<String, List<WorkOrderLineItem>>();
        for (WorkOrderLineItem woli : readings) {
            String code = woli.Measurement_Item_Code__c;
            if (!byItem.containsKey(code)) {
                byItem.put(code, new List<WorkOrderLineItem>());
            }
            byItem.get(code).add(woli);
        }

        List<GaugeInfo> gauges = new List<GaugeInfo>();
        for (String code : byItem.keySet()) {
            List<WorkOrderLineItem> rows = byItem.get(code);
            WorkOrderLineItem latest = rows[0];

            GaugeInfo g = new GaugeInfo();
            g.measurementItemCode = code;
            g.trendFlag = latest.Trend_Flag__c;
            g.abnormal = ATTENTION_FLAGS.contains(latest.Trend_Flag__c);
            g.currentValue = latest.Measured_Value__c;
            g.deltaFromPrevious = latest.Delta_From_Previous__c;
            g.previousValue = (latest.Previous_Measured_Value__c != null)
                ? latest.Previous_Measured_Value__c
                : (latest.Delta_From_Previous__c != null
                    ? latest.Measured_Value__c - latest.Delta_From_Previous__c
                    : null);
            g.baselineValue = latest.Baseline_Value__c;

            // 현재 이상 추세가 얼마나 지속됐는지: 최신부터 연속으로 주의/이상인
            // 구간의 가장 오래된 측정 시각을 기산점으로 삼는다.
            if (g.abnormal) {
                Datetime streakStart = latest.CreatedDate;
                for (WorkOrderLineItem row : rows) {
                    if (ATTENTION_FLAGS.contains(row.Trend_Flag__c)) {
                        streakStart = row.CreatedDate;
                    } else {
                        break;
                    }
                }
                g.streakStart = streakStart;
            }
            gauges.add(g);
        }
        return gauges;
    }

    /** 이상(주의/이상) 항목을 우선, 없으면 첫 항목. */
    // primary 게이지 선택 우선순위 — 냉각 장비 핵심 지표 순(유량 > 차압 > 수온).
    // 진단 첫 응답의 주인공을 결정한다.
    private static final List<String> PRIMARY_PRIORITY = new List<String>{ '유량', '차압', '수온' };
    public static GaugeInfo pickPrimary(List<GaugeInfo> gauges) {
        if (gauges == null || gauges.isEmpty()) {
            return null;
        }
        // 1순위: 우선순위 코드 순서로 abnormal 게이지를 찾는다.
        for (String code : PRIMARY_PRIORITY) {
            for (GaugeInfo g : gauges) {
                if (g.abnormal && code.equals(g.measurementItemCode)) {
                    return g;
                }
            }
        }
        // 2순위: 우선순위에 없는 abnormal 게이지.
        for (GaugeInfo g : gauges) {
            if (g.abnormal) {
                return g;
            }
        }
        // 3순위: abnormal이 없으면 우선순위 순의 첫 게이지, 없으면 목록 첫 게이지.
        for (String code : PRIMARY_PRIORITY) {
            for (GaugeInfo g : gauges) {
                if (code.equals(g.measurementItemCode)) {
                    return g;
                }
            }
        }
        return gauges[0];
    }

    /**
     * 게이지 전체를 Agent가 그대로 읽어 말할 수 있는 한국어 요약으로 만든다.
     * 값은 전부 실측(WOLI)에서 왔고, 단위·기준선 범위만 표현을 붙인다.
     */
    public static String formatGaugesSummary(List<GaugeInfo> gauges) {
        if (gauges == null || gauges.isEmpty()) {
            return '실시간 측정 이력이 아직 없습니다.';
        }
        List<String> lines = new List<String>();
        for (GaugeInfo g : gauges) {
            String unit = unitFor(g.measurementItemCode);
            String line = g.measurementItemCode + ': 현재 '
                + trimDecimal(g.currentValue) + unit;
            String range = formatBaselineRange(g);
            if (range != null) {
                line += ' · 기준선 ' + range;
            }
            line += ' · 추세 ' + (String.isBlank(g.trendFlag) ? '미판정' : g.trendFlag);
            if (g.deltaFromPrevious != null) {
                String sign = g.deltaFromPrevious >= 0 ? '+' : '';
                line += ' (직전 대비 ' + sign + trimDecimal(g.deltaFromPrevious) + unit + ')';
            }
            if (g.abnormal && g.streakStart != null) {
                line += ' · ' + g.trendFlag + ' 지속 ' + formatDuration(g.streakStart);
            }
            lines.add(line);
        }
        return String.join(lines, '\n');
    }

    /** 기준선을 단일값 ± 허용오차(±10%)로 표현한 범위 문자열. (a)안 — 필드 신설 없음. */
    private static final Decimal BASELINE_TOLERANCE_PCT = 10;
    public static String formatBaselineRange(GaugeInfo g) {
        if (g == null || g.baselineValue == null) {
            return null;
        }
        Decimal band = (g.baselineValue.abs() * BASELINE_TOLERANCE_PCT / 100).setScale(0);
        Decimal low = g.baselineValue - band;
        Decimal high = g.baselineValue + band;
        String unit = unitFor(g.measurementItemCode);
        return trimDecimal(low) + '–' + trimDecimal(high) + unit;
    }

    /**
     * 이 자산의 완료된 서비스/정비 이력을 최신순으로 요약한다. 정비 이력
     * 관련목록(완료된 WorkOrder)을 그대로 읽기만 한다 — 새 상태 계산 없음.
     */
    public static String formatMaintenanceHistory(Id assetId) {
        List<WorkOrder> history = [
            SELECT Subject, Status, StartDate, WorkType.Name, CreatedDate
            FROM WorkOrder
            WHERE AssetId = :assetId
              AND Status = 'Completed'
            ORDER BY StartDate DESC NULLS LAST, CreatedDate DESC
            LIMIT 8
        ];
        if (history.isEmpty()) {
            return '완료된 정비 이력이 없습니다.';
        }
        List<String> lines = new List<String>();
        for (WorkOrder wo : history) {
            Date d = wo.StartDate != null ? wo.StartDate.date() : wo.CreatedDate.date();
            String label = String.isNotBlank(wo.Subject)
                ? wo.Subject
                : (wo.WorkType != null ? wo.WorkType.Name : '서비스 작업');
            lines.add(String.valueOf(d) + '  ' + label + ' 완료');
        }
        return String.join(lines, '\n');
    }

    private static final Set<String> ATTENTION_FLAGS = new Set<String>{ '주의', '이상' };

    private static final Map<String, String> UNITS = new Map<String, String>{
        '유량' => ' L/min',
        '차압' => ' kPa',
        '수온' => ' °C',
        '전류' => ' A',
        '체결토크' => ' N·m'
    };
    private static String unitFor(String code) {
        String u = UNITS.get(code);
        return u == null ? '' : u;
    }

    /** 소수점 뒤 불필요한 0을 없앤 값 문자열(2200.00 → 2200, 18.20 → 18.2). */
    private static String trimDecimal(Decimal d) {
        if (d == null) {
            return '';
        }
        Decimal stripped = d.stripTrailingZeros();
        // 10의 배수(예: 20)는 stripTrailingZeros가 scale을 음수로 만들어
        // String.valueOf가 '2E+1' 같은 과학표기법을 뱉는다. scale을 0으로 되돌린다.
        if (stripped.scale() < 0) {
            stripped = stripped.setScale(0);
        }
        return String.valueOf(stripped);
    }

    /** 기산점부터 지금까지 경과를 사람이 읽는 단위로. 실측 타임스탬프 기반. */
    public static String formatDuration(Datetime since) {
        if (since == null) {
            return null;
        }
        Long minutes = (System.now().getTime() - since.getTime()) / 60000;
        if (minutes < 1) {
            return '방금';
        }
        if (minutes < 60) {
            return minutes + '분';
        }
        Long hours = minutes / 60;
        if (hours < 24) {
            return hours + '시간';
        }
        return (hours / 24) + '일';
    }

    /**
     * A안(2026-08-31) — Agent 런타임이 sessionId 바인딩을 액션에 전달하지 않는 것이
     * 확정돼(채널 핸들러 AgentforceServiceAgent 제약), sessionId를 신뢰하지 않고
     * 없으면 "가장 최근에 Asset_Id__c가 채워진 세션"을 직접 찾는다.
     * ⚠️ 다수 동시 접속 시 세션 구분이 깨질 수 있는 데모용 heuristic. 프로덕션
     * 근본 해결은 채널 재구성(작업기록 T5-08 5절 D 참조).
     */
    public static Id resolveAssetIdForAgent(String sessionIdStr) {
        // 1순위: 넘어온 sessionId가 유효하면 그 세션을 그대로 쓴다.
        if (String.isNotBlank(sessionIdStr)) {
            try {
                Id sessionId = Id.valueOf(sessionIdStr);
                List<MessagingSession> sessions = [
                    SELECT Asset_Id__c FROM MessagingSession WHERE Id = :sessionId LIMIT 1
                ];
                if (!sessions.isEmpty() && String.isNotBlank(sessions[0].Asset_Id__c)) {
                    Id aId = Id.valueOf(sessions[0].Asset_Id__c);
                    if (aId.getSObjectType() == Asset.SObjectType) {
                        return aId;
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, '[T5-23] sessionId parse failed: ' + e.getMessage());
            }
        }

        // 2순위(A안 heuristic): sessionId가 없거나 무효 → 가장 최근에
        // Asset_Id__c가 채워진 MessagingSession.
        List<MessagingSession> recent = [
            SELECT Asset_Id__c FROM MessagingSession
            WHERE Asset_Id__c != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (recent.isEmpty() || String.isBlank(recent[0].Asset_Id__c)) {
            return null;
        }
        try {
            Id assetId = Id.valueOf(recent[0].Asset_Id__c);
            return assetId.getSObjectType() == Asset.SObjectType ? assetId : null;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[T5-23] heuristic parse failed: ' + e.getMessage());
            return null;
        }
    }

    /** 측정 항목 하나의 실시간 상태 — 두 액션이 공유하는 내부 표현. */
    public class GaugeInfo {
        public String measurementItemCode;
        public String trendFlag;
        public Boolean abnormal;
        public Decimal currentValue;
        public Decimal previousValue;
        public Decimal deltaFromPrevious;
        public Decimal baselineValue;
        public Datetime streakStart;
    }

    public class AssetContextInput {
        @InvocableVariable(label='Session Id' description='현재 MessagingSession Id(RoutableId). 없으면 최근 자산 세션을 heuristic으로 찾는다.' required=false)
        public String sessionId;
    }

    public class AssetContextOutput {
        @InvocableVariable(label='Found') public Boolean found;
        @InvocableVariable(label='Asset Name') public String assetName;
        @InvocableVariable(label='Serial Number') public String serialNumber;
        @InvocableVariable(label='Asset Type') public String assetType;
        @InvocableVariable(label='State Label') public String stateLabel;
        @InvocableVariable(label='Warranty Type') public String warrantyType;
        @InvocableVariable(label='Open Items Summary') public Decimal openItemsSummary;
        @InvocableVariable(label='Gauges Summary' description='전 측정 항목의 현재값·기준선·추세·지속시간 요약(실측 WOLI 기반). Agent가 그대로 읽어 말한다.') public String gaugesSummary;
        @InvocableVariable(label='Maintenance History' description='완료된 정비 이력 최신순 요약(실측 WorkOrder 기반).') public String maintenanceHistory;
        @InvocableVariable(label='Measurement Item Code') public String measurementItemCode;
        @InvocableVariable(label='Trend Flag') public String trendFlag;
        @InvocableVariable(label='Current Value') public String currentValue;
        @InvocableVariable(label='Previous Value') public String previousValue;
        @InvocableVariable(label='Baseline Range') public String baselineRange;
        @InvocableVariable(label='Advisory Duration') public String advisoryDuration;
        @InvocableVariable(label='Error Message') public String errorMessage;
    }
}

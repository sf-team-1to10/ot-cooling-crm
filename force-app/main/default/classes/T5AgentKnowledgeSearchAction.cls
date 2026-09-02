/**
 * T5-22 — Agent(증상 상담)가 Case 생성 전에 게시된 고객용 Knowledge Article을
 * 검색하는 Invocable Action. 매치되면 자가 해결을 유도하고, 없으면 Case 생성
 * 단계로 넘어가면서 Case.Knowledge_No_Match_At_Intake__c를 체크할 근거가 된다.
 *
 * 지금은 게시된 고객용(Online·IsVisibleInCsp) Article이 데모 1건뿐이라 SOSL
 * 전문검색 대신 단순 키워드 부분일치로 충분하다 — Article 수가 늘어나면
 * SOSL(FIND ... RETURNING Knowledge__kav)로 교체할 것(후속 트래커 항목).
 *
 * 키워드는 질문이 아니라 Article Title에서 뽑아 질문 원문 전체에 포함되는지
 * 본다(방향 반대로 하면 한국어 조사 때문에 "유량"↔"유량이"가 안 맞음).
 * Summary는 일반 단어가 많아 키워드 소스에서 제외, Title도 흔한 단어는
 * STOPWORDS로 거른다.
 */
public without sharing class T5AgentKnowledgeSearchAction {

    @InvocableMethod(
        label='Search Knowledge Articles'
        description='고객이 설명한 증상 키워드로 게시된(Online, 고객 포털 공개) Knowledge Article을 찾는다. 매치되면 제목·요약을 돌려주고, 없으면 found=false.'
    )
    public static List<SearchOutput> search(List<SearchInput> inputs) {
        List<SearchOutput> results = new List<SearchOutput>();
        for (SearchInput inp : inputs) {
            results.add(execute(inp));
        }
        return results;
    }

    private static SearchOutput execute(SearchInput inp) {
        SearchOutput out = new SearchOutput();
        out.found = false;
        out.assetFound = false;
        attachAssetContext(inp.sessionId, out);
        if (String.isBlank(inp.queryText)) {
            return out;
        }

        // 방향 주의: 키워드는 "질문"이 아니라 "Article"에서 뽑는다. 한국어는
        // 조사가 명사에 바로 붙는다("유량" + "이" → "유량이") — 질문 쪽 토큰을
        // 키워드로 쓰면 "유량이"가 Article의 "유량"과 정확히 안 맞아 매칭이
        // 깨진다(2026-08-30 실측 확인, CLI 프리뷰에서 "유량이 기준보다 낮은
        // 것 같아요"가 found=false로 나왔던 원인). Article 쪽 명사(대개
        // 조사 없이 깨끗하게 등장)를 키워드로 뽑아 질문 원문 전체 안에
        // 부분일치로 찾으면, "유량"이 "유량이"의 부분 문자열이라 자연스럽게
        // 잡힌다.
        String queryLower = inp.queryText.toLowerCase();

        // WITH USER_MODE를 안 쓴다 — 이 클래스는 이미 without sharing이고,
        // 검색 대상은 "이미 게시(Online)·고객 공개(IsVisibleInCsp) 설정된
        // 콘텐츠"뿐이라 애초에 개인화된 레코드 공유가 필요 없다. 실측으로
        // 확인(2026-08-30): WITH USER_MODE를 걸면 Agent 실행 계정(포털
        // 라이선스 사용자가 아닌 특수 통합 계정)이 FLS를 다 갖고 있어도
        // Knowledge의 IsVisibleInCsp 공유 판정에서 막혀 항상 0건이 나옴 —
        // 형제 클래스 T5AgentCaseIntakeAction도 같은 이유로 WITH USER_MODE를
        // 안 쓰는 것과 같은 패턴으로 맞춤.
        List<Knowledge__kav> articles = [
            SELECT Title, Summary, UrlName
            FROM Knowledge__kav
            WHERE PublishStatus = 'Online' AND IsVisibleInCsp = true
            LIMIT 50
        ];

        for (Knowledge__kav article : articles) {
            // Summary(본문)까지 키워드로 뽑으면 "확인"·"안내" 같은 흔한 일반
            // 단어가 섞여 아무 문의에나 오탐 매칭될 위험이 크다 — Title(짧고
            // 핵심 명사 위주)만 키워드 소스로 쓴다. Article이 늘어나 Title이
            // 다양해지면 이 정도로도 변별력은 충분하다.
            Set<String> articleKeywords = extractKeywords(article.Title);
            for (String kw : articleKeywords) {
                if (queryLower.contains(kw)) {
                    out.found = true;
                    out.articleTitle = article.Title;
                    out.articleSummary = article.Summary;
                    out.articleUrlName = article.UrlName;
                    return out;
                }
            }
        }
        return out;
    }

    private static void attachAssetContext(String sessionIdStr, SearchOutput out) {
        try {
            Id assetId = T5AgentAssetContextAction.resolveAssetIdForAgent(sessionIdStr);
            if (assetId == null) {
                return;
            }
            List<Asset> assets = [
                SELECT Id, Name, SerialNumber, Product2.Name,
                       Warranty_Type__c, Open_Items_Summary__c
                FROM Asset WHERE Id = :assetId LIMIT 1
            ];
            if (assets.isEmpty()) {
                return;
            }
            Asset a = assets[0];

            // 게이지는 Asset 스냅샷이 아니라 IoT가 흘려보낸 WOLI 측정 이력을
            // 실시간으로 읽는다(T5AgentAssetContextAction와 단일 소스 공유).
            List<T5AgentAssetContextAction.GaugeInfo> gauges =
                T5AgentAssetContextAction.resolveGaugesForAgent(assetId);
            T5AgentAssetContextAction.GaugeInfo primary =
                T5AgentAssetContextAction.pickPrimary(gauges);
            Boolean anyAbnormal = false;
            for (T5AgentAssetContextAction.GaugeInfo g : gauges) {
                if (g.abnormal) { anyAbnormal = true; break; }
            }

            out.assetFound = true;
            out.assetName = a.Name;
            out.serialNumber = a.SerialNumber;
            out.assetType = a.Product2 != null ? a.Product2.Name : '';
            out.stateLabel = anyAbnormal ? 'P3 Advisory / 주의' : '정상';
            out.warrantyType = a.Warranty_Type__c;
            out.openItemsSummary = a.Open_Items_Summary__c;
            out.gaugesSummary = T5AgentAssetContextAction.formatGaugesSummary(gauges);
            if (primary != null) {
                out.measurementItemCode = primary.measurementItemCode;
                out.trendFlag = primary.trendFlag;
                out.currentValue = primary.currentValue != null ? String.valueOf(primary.currentValue) : null;
                out.previousValue = primary.previousValue != null ? String.valueOf(primary.previousValue) : null;
                out.baselineRange = T5AgentAssetContextAction.formatBaselineRange(primary);
                out.advisoryDuration = primary.abnormal ? T5AgentAssetContextAction.formatDuration(primary.streakStart) : null;
            }
        } catch (Exception e) {
            // silent — asset context is best-effort
        }
    }

    /** 흔한 일반 단어·조사성 잡음을 걸러낸 2글자 이상 토큰만 키워드로 쓴다. */
    private static final Set<String> STOPWORDS = new Set<String>{
        '확인', '안내', '알림', '시', '및', '등', '또는', '그리고', '데모', '고객', '방법'
    };
    private static Set<String> extractKeywords(String text) {
        Set<String> keywords = new Set<String>();
        if (String.isBlank(text)) {
            return keywords;
        }
        for (String token : text.toLowerCase().split('[\\s,.!?~()]+')) {
            if (token.length() >= 2 && !STOPWORDS.contains(token)) {
                keywords.add(token);
            }
        }
        return keywords;
    }

    public class SearchInput {
        @InvocableVariable(label='Query Text' description='고객이 설명한 증상 원문 또는 핵심 키워드' required=true)
        public String queryText;
        @InvocableVariable(label='Session Id' description='현재 MessagingSession Id — 자산 컨텍스트를 함께 반환한다.' required=false)
        public String sessionId;
    }

    public class SearchOutput {
        @InvocableVariable(label='Found')
        public Boolean found;
        @InvocableVariable(label='Article Title')
        public String articleTitle;
        @InvocableVariable(label='Article Summary')
        public String articleSummary;
        @InvocableVariable(label='Article Url Name')
        public String articleUrlName;
        @InvocableVariable(label='Asset Found') public Boolean assetFound;
        @InvocableVariable(label='Asset Name') public String assetName;
        @InvocableVariable(label='Serial Number') public String serialNumber;
        @InvocableVariable(label='Asset Type') public String assetType;
        @InvocableVariable(label='State Label') public String stateLabel;
        @InvocableVariable(label='Warranty Type') public String warrantyType;
        @InvocableVariable(label='Open Items Summary') public Decimal openItemsSummary;
        @InvocableVariable(label='Gauges Summary' description='전 측정 항목의 현재값·기준선·추세·지속시간 요약(실측 WOLI 기반).') public String gaugesSummary;
        @InvocableVariable(label='Measurement Item Code') public String measurementItemCode;
        @InvocableVariable(label='Trend Flag') public String trendFlag;
        @InvocableVariable(label='Current Value') public String currentValue;
        @InvocableVariable(label='Previous Value') public String previousValue;
        @InvocableVariable(label='Baseline Range') public String baselineRange;
        @InvocableVariable(label='Advisory Duration') public String advisoryDuration;
    }
}
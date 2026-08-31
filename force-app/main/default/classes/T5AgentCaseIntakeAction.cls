public without sharing class T5AgentCaseIntakeAction {

    @InvocableMethod(
        label='Create Case from Agent Consultation'
        description='Agent가 고객 대화에서 파악한 증상·영향을 기존 Case 생성 로직으로 접수한다. 폼(otReportFault)과 동일한 필드·자동화를 탄다.'
    )
    public static List<CaseOutput> createCase(List<CaseInput> inputs) {
        List<CaseOutput> results = new List<CaseOutput>();
        for (CaseInput inp : inputs) {
            results.add(execute(inp));
        }
        return results;
    }

    private static CaseOutput execute(CaseInput inp) {
        CaseOutput out = new CaseOutput();

        if (String.isBlank(inp.assetId)) {
            out.success = false;
            out.errorMessage = '자산이 선택되지 않았습니다.';
            return out;
        }
        if (String.isBlank(inp.symptomCategory)) {
            out.success = false;
            out.errorMessage = '증상 분류가 필요합니다.';
            return out;
        }
        if (String.isBlank(inp.impactLevel)) {
            out.success = false;
            out.errorMessage = '영향 등급이 필요합니다.';
            return out;
        }
        if (String.isBlank(inp.reportedSymptom)) {
            out.success = false;
            out.errorMessage = '고객 진술이 필요합니다.';
            return out;
        }

        try {
            Id accountHint = resolveAccountFromContact(inp.contactId);
            Asset asset = resolveAsset(inp.assetId, accountHint);
            if (asset == null) {
                out.success = false;
                out.errorMessage = '입력하신 장비 정보로 등록된 자산을 찾지 못했습니다: ' + inp.assetId;
                return out;
            }

            Id contactId = resolveContact(inp.contactId, asset.AccountId);

            Case newCase = new Case(
                AssetId = asset.Id,
                AccountId = asset.AccountId,
                ContactId = contactId,
                Origin = 'Agent',
                Subject = inp.symptomCategory,
                Symptom_Category__c = inp.symptomCategory,
                Impact_Level__c = normalizeImpactLevel(inp.impactLevel),
                Reported_Symptom__c = inp.reportedSymptom,
                // T5-22: Agent Script에서 "매치 없음"을 표현식으로 반전시키면
                // 검증 안 된 문법 위험이 생겨서, 반전 계산을 여기 Apex로 옮김 —
                // Agent는 검색 결과(found) 그대로만 넘긴다. found가 true가
                // 아니면(false 또는 애초에 안 넘어옴) "매치 없음"으로 간주해
                // Case Closed 시 Article 등록 제안 배너의 트리거 조건이 된다.
                Knowledge_No_Match_At_Intake__c = inp.knowledgeFound != true
            );
            insert newCase;

            // T5-23: 이관(escalate) 시 상담사가 큐에서 Accept한 세션이 어떤
            // Case인지 알아야 Case 레코드로 이어갈 수 있다. MessagingSession
            // 표준 필드 CaseId에 방금 만든 Case를 바로 연결해둔다 — 이관은
            // 이 Case 생성 다음에 일어나므로, 이관 시점엔 이미 연결돼 있다.
            if (String.isNotBlank(inp.sessionId)) {
                try {
                    Id sessionId = Id.valueOf(inp.sessionId);
                    update new MessagingSession(Id = sessionId, CaseId = newCase.Id);
                } catch (Exception ignoreLinkError) {
                    // 세션 연결 실패는 Case 접수 자체를 막지 않는다 — 조용히 넘어감.
                }
            }

            Case saved = [
                SELECT CaseNumber, Account.Name,
                       Warranty_Decision__c, Coverage_Type__c, Billable__c
                FROM Case WHERE Id = :newCase.Id LIMIT 1
            ];

            out.success = true;
            out.caseId = saved.Id;
            out.caseNumber = saved.CaseNumber;
            out.accountName = saved.Account != null ? saved.Account.Name : '';
            out.warrantyDecision = saved.Warranty_Decision__c;
            out.coverageType = saved.Coverage_Type__c;
            out.billable = saved.Billable__c;
        } catch (Exception e) {
            out.success = false;
            out.errorMessage = e.getMessage();
        }
        return out;
    }

    /**
     * assetId 입력은 두 가지 형태로 들어올 수 있다:
     * 1) 실제 Salesforce Id — 포털 컨텍스트가 이미 알고 있는 자산을 넘겨주는
     *    미래 시나리오(T5-23 실시간 채널 연결 후 예정). 이 경우 바로 조회.
     * 2) 고객이 대화 중 말한 장비명/위치 자유 텍스트(예: "CDU-A-07 홀 A 3번") —
     *    현재 Builder/CLI 대화에서 실제로 발생하는 형태. Id.valueOf가 실패하면
     *    Asset.Name이 입력 텍스트 안에 부분 문자열로 포함되는지로 찾는다
     *    (T5AgentKnowledgeSearchAction의 키워드 방향과 동일한 패턴 — 후보를
     *    원문에서 찾는 대신, 원문 안에 후보가 포함되는지를 본다).
     */
    private static Asset resolveAsset(String assetIdOrText, Id accountHint) {
        if (String.isBlank(assetIdOrText)) {
            return null;
        }

        try {
            Id maybeId = Id.valueOf(assetIdOrText);
            if (maybeId.getSObjectType() == Asset.SObjectType) {
                List<Asset> byId = [
                    SELECT Id, Name, AccountId FROM Asset
                    WHERE Id = :maybeId LIMIT 1
                ];
                if (!byId.isEmpty()) {
                    return byId[0];
                }
            }
        } catch (Exception e) {
            // 유효한 Id 형식이 아님 — 자유 텍스트로 간주하고 아래에서 이름 매칭 시도
        }

        String textUpper = assetIdOrText.toUpperCase();
        List<Asset> candidates = accountHint != null
            ? [SELECT Id, Name, AccountId FROM Asset WHERE AccountId = :accountHint LIMIT 200]
            : [SELECT Id, Name, AccountId FROM Asset LIMIT 200];

        Asset bestMatch = null;
        for (Asset a : candidates) {
            if (String.isNotBlank(a.Name) && textUpper.contains(a.Name.toUpperCase())) {
                // 여러 후보가 부분일치하면 이름이 더 긴(더 구체적인) 쪽을 우선한다.
                if (bestMatch == null || a.Name.length() > bestMatch.Name.length()) {
                    bestMatch = a;
                }
            }
        }
        return bestMatch;
    }

    /**
     * Impact_Level__c은 제한된(restricted) 피클리스트라 "S3 일반"처럼 코드+
     * 한글 라벨 전체가 정확히 일치해야 값이 들어간다(2026-08-30 실측:
     * Tooling API로 valueSet 직접 확인). Agent는 대화 흐름에 따라 "S3"만
     * 보내기도 하고 "S3 일반"을 그대로 보내기도 해서 일관되지 않았고, 이
     * 불일치 때문에 실제 Live Test에서 INVALID_FIELD_FOR_INSERT_UPDATE 성격의
     * 피클리스트 오류로 접수가 조용히 실패한 적이 있었다(Trace로 확인). LLM
     * 출력 표기를 신뢰하지 않고 여기서 정규화한다.
     */
    private static final Map<String, String> IMPACT_LEVEL_CANONICAL = new Map<String, String>{
        'S1' => 'S1 긴급',
        'S2' => 'S2 중요',
        'S3' => 'S3 일반',
        'S4' => 'S4 요청'
    };

    private static String normalizeImpactLevel(String raw) {
        if (String.isBlank(raw)) {
            return raw;
        }
        String upper = raw.toUpperCase();
        for (String prefix : IMPACT_LEVEL_CANONICAL.keySet()) {
            if (upper.contains(prefix)) {
                return IMPACT_LEVEL_CANONICAL.get(prefix);
            }
        }
        // S1~S4 어디에도 안 걸리면 원본 그대로 넘겨서, 실제 피클리스트 오류로
        // 정직하게 실패하게 둔다(임의로 기본값을 넣지 않음 — 등급 오분류 방지).
        return raw;
    }

    private static Id resolveAccountFromContact(String contactIdStr) {
        if (String.isBlank(contactIdStr)) {
            return null;
        }
        try {
            Id cid = Id.valueOf(contactIdStr);
            List<Contact> cs = [SELECT AccountId FROM Contact WHERE Id = :cid LIMIT 1];
            return cs.isEmpty() ? null : cs[0].AccountId;
        } catch (Exception e) {
            return null;
        }
    }

    private static Id resolveContact(String contactIdStr, Id accountId) {
        if (String.isNotBlank(contactIdStr)) {
            try {
                return Id.valueOf(contactIdStr);
            } catch (Exception e) { /* fall through */ }
        }
        List<Contact> contacts = [
            SELECT Id FROM Contact
            WHERE AccountId = :accountId
            ORDER BY CreatedDate ASC LIMIT 1
        ];
        return contacts.isEmpty() ? null : contacts[0].Id;
    }

    public class CaseInput {
        @InvocableVariable(label='Asset Id' description='장애 대상 자산의 Salesforce Id 또는 고객이 말한 장비명/위치(예: CDU-A-07)' required=true)
        public String assetId;

        @InvocableVariable(label='Symptom Category' description='증상 분류 (유량저하/누수/소음/제어이상/전원/기타)' required=true)
        public String symptomCategory;

        @InvocableVariable(label='Impact Level' description='영향 등급 (S1 긴급/S2 중요/S3 일반/S4 요청)' required=true)
        public String impactLevel;

        @InvocableVariable(label='Reported Symptom' description='고객이 설명한 증상 원문' required=true)
        public String reportedSymptom;

        @InvocableVariable(label='Contact Id' description='고객 담당자 Id (선택, 없으면 Account의 첫 Contact 사용)')
        public String contactId;

        @InvocableVariable(label='Knowledge Found' description='Case 생성 전 Knowledge 검색에서 매치되는 Article을 찾았으면 true (T5-22, search_knowledge Action의 found 값을 그대로 전달)')
        public Boolean knowledgeFound;

        @InvocableVariable(label='Session Id' description='현재 MessagingSession Id(RoutableId). 이 Case를 그 세션에 즉시 연결해, 나중에 이관·Accept 시 상담사가 Case로 이어갈 수 있게 한다.')
        public String sessionId;
    }

    public class CaseOutput {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Case Id')
        public String caseId;

        @InvocableVariable(label='Case Number')
        public String caseNumber;

        @InvocableVariable(label='Account Name')
        public String accountName;

        @InvocableVariable(label='Warranty Decision')
        public String warrantyDecision;

        @InvocableVariable(label='Coverage Type')
        public String coverageType;

        @InvocableVariable(label='Billable')
        public Boolean billable;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }
}

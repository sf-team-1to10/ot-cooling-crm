/**
 * T5AgentKnowledgeSearchAction 테스트.
 *
 * ⚠ "매치됨(found=true)" 경로는 여기서 단위 테스트로 못 돌린다 — Knowledge
 * Article을 만들고(insert) 발행(KbManagement.PublishingService.publishArticle)한
 * 뒤 같은 트랜잭션/테스트 컨텍스트 안에서 바로 쿼리하면 IsVisibleInCsp 등
 * 채널 공개 상태가 반영되지 않는 걸 실측으로 확인했다(2026-08-30 —
 * @TestSetup, Test.startTest/stopTest로 감싸기, SeeAllData=true 전부 시도했지만
 * 동일하게 실패). Knowledge 발행이 비동기·특수 트랜잭션으로 처리돼 테스트
 * 격리와 근본적으로 안 맞는 것으로 보인다(Salesforce Knowledge의 알려진
 * 테스트 제약).
 *
 * 대신 이 경로는 **실제 org에서 익명 Apex로 두 번 실측 검증**했다 — 데모
 * Article(ka0h80000000LinAAE, "냉각수 유량 저하 알림 시 확인 안내 (데모)")을
 * 만들고 발행 상태까지 확인한 게 그 증거(작업기록 참고:
 * `ot-cooling-crm 개발/t5/T5_서비스에이전트_작업기록.md`). 여기서는 검색 로직
 * 자체(빈 입력·매치 없는 키워드 처리)만 단위 테스트로 남긴다.
 */
@IsTest
private class T5AgentKnowledgeSearchActionTest {

    @IsTest
    static void search_returnsNotFoundForUnrelatedSymptom() {
        T5AgentKnowledgeSearchAction.SearchInput input = new T5AgentKnowledgeSearchAction.SearchInput();
        input.queryText = '전원이 안 들어와요';

        Test.startTest();
        List<T5AgentKnowledgeSearchAction.SearchOutput> results =
            T5AgentKnowledgeSearchAction.search(new List<T5AgentKnowledgeSearchAction.SearchInput>{ input });
        Test.stopTest();

        System.assertEquals(false, results[0].found);
        System.assertEquals(null, results[0].articleTitle);
    }

    @IsTest
    static void search_returnsNotFoundForBlankQuery() {
        T5AgentKnowledgeSearchAction.SearchInput input = new T5AgentKnowledgeSearchAction.SearchInput();
        input.queryText = '';

        Test.startTest();
        List<T5AgentKnowledgeSearchAction.SearchOutput> results =
            T5AgentKnowledgeSearchAction.search(new List<T5AgentKnowledgeSearchAction.SearchInput>{ input });
        Test.stopTest();

        System.assertEquals(false, results[0].found);
    }

    @IsTest
    static void search_handlesMultipleInputsInOneCall() {
        T5AgentKnowledgeSearchAction.SearchInput a = new T5AgentKnowledgeSearchAction.SearchInput();
        a.queryText = '전원이 안 들어와요';
        T5AgentKnowledgeSearchAction.SearchInput b = new T5AgentKnowledgeSearchAction.SearchInput();
        b.queryText = '';

        Test.startTest();
        List<T5AgentKnowledgeSearchAction.SearchOutput> results =
            T5AgentKnowledgeSearchAction.search(
                new List<T5AgentKnowledgeSearchAction.SearchInput>{ a, b }
            );
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(false, results[0].found);
        System.assertEquals(false, results[1].found);
    }
}
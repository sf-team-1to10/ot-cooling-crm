/**
 * T5AgentEntitlementContextAction 테스트.
 *
 * 이 액션은 assetId를 T5AgentAssetContextAction.resolveAssetIdForAgent(세션
 * 기반)로 찾은 뒤 ServiceContract·Entitlement를 조회한다. MessagingSession
 * 레코드는 org의 메시징 채널 설정에 의존적이라 테스트에서 안정적으로 만들 수
 * 없어, 세션이 해석되지 않는 경우의 fallback 경로(usingFallback=true)를 중심으로
 * 커버한다. fallback은 실 계약/보증 레코드가 없을 때 데모값을 반환하는,
 * 프로덕션 승격 전 A안의 실제 런타임 경로다.
 */
@IsTest
private class T5AgentEntitlementContextActionTest {

    @IsTest
    static void getContext_returnsFallback_WhenAssetUnresolvable() {
        T5AgentEntitlementContextAction.EntitlementInput inp =
            new T5AgentEntitlementContextAction.EntitlementInput();
        inp.sessionId = '';

        Test.startTest();
        List<T5AgentEntitlementContextAction.EntitlementOutput> outs =
            T5AgentEntitlementContextAction.getContext(
                new List<T5AgentEntitlementContextAction.EntitlementInput>{ inp }
            );
        Test.stopTest();

        Assert.areEqual(1, outs.size(), '입력 하나당 출력 하나');
        T5AgentEntitlementContextAction.EntitlementOutput out = outs[0];
        Assert.areEqual(true, out.found, 'fallback도 found=true로 답한다');
        Assert.areEqual(true, out.usingFallback,
            '자산 식별 불가 시 데모 fallback 경로를 타야 한다');
        Assert.areEqual(true, out.serviceContractActive,
            'fallback은 계약 활성으로 안내');
        Assert.areEqual(true, out.warrantyActive, 'fallback은 보증 활성으로 안내');
        Assert.isNotNull(out.responseTarget, '응답 목표가 채워져야 한다');
        Assert.isNotNull(out.coverageScope, '적용 범위가 채워져야 한다');
        Assert.isNotNull(out.billableNote, '유상 안내 문구가 채워져야 한다');
    }

    @IsTest
    static void getContext_setsErrorNote_WhenAssetUnresolvable() {
        // sessionId가 무효 → 자산 식별 불가 → fallback + 안내 note.
        T5AgentEntitlementContextAction.EntitlementInput inp =
            new T5AgentEntitlementContextAction.EntitlementInput();
        inp.sessionId = 'not-a-valid-id';

        Test.startTest();
        List<T5AgentEntitlementContextAction.EntitlementOutput> outs =
            T5AgentEntitlementContextAction.getContext(
                new List<T5AgentEntitlementContextAction.EntitlementInput>{ inp }
            );
        Test.stopTest();

        Assert.areEqual(true, outs[0].usingFallback,
            '무효 sessionId면 자산을 못 찾아 fallback으로 떨어진다');
        Assert.isNotNull(outs[0].errorMessage,
            '자산 식별 불가 안내 note가 채워져야 한다');
    }

    @IsTest
    static void getContext_handlesMultipleInputs() {
        T5AgentEntitlementContextAction.EntitlementInput a =
            new T5AgentEntitlementContextAction.EntitlementInput();
        a.sessionId = '';
        T5AgentEntitlementContextAction.EntitlementInput b =
            new T5AgentEntitlementContextAction.EntitlementInput();
        b.sessionId = 'not-a-valid-id';

        Test.startTest();
        List<T5AgentEntitlementContextAction.EntitlementOutput> outs =
            T5AgentEntitlementContextAction.getContext(
                new List<T5AgentEntitlementContextAction.EntitlementInput>{ a, b }
            );
        Test.stopTest();

        Assert.areEqual(2, outs.size(), '입력 수만큼 출력이 나와야 한다');
        Assert.areEqual(true, outs[0].found);
        Assert.areEqual(true, outs[1].found);
    }
}

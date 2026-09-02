/**
 * T5-08 대화 고도화 — Agent가 "이 Case에 어떤 지원 조건이 적용되는가"(서비스 계약
 * 활성 여부·보증 활성 여부·초기 응답 목표·적용 범위)를 답하기 위한 Invocable Action.
 *
 * 설계 원칙(작업기록 T5-08 5절 F): 지원 조건 값을 Agent Script에 하드코딩하지
 * 않는다. Script는 "지원 조건은 이 액션 결과로 답하라"고만 지시하고, 값은 전부
 * 여기서 나온다.
 *
 * A안(데모) ↔ B안(프로덕션)의 경계가 이 클래스 안에 있다:
 *  - 이미 실 Entitlement/ServiceContract를 조회한다. 레코드가 있으면 실값을 돌려준다.
 *  - 레코드가 없으면(현재 T3DLV 상태) 데모 fallback 값을 돌려주고 usingFallback=true로 표시.
 * → 프로덕션 승격은 "코드 교체"가 아니라 "데이터 시딩"만으로 끝난다. Entitlement·
 *   ServiceContract를 넣는 순간 이 액션이 자동으로 실값 경로로 전환된다.
 */
public without sharing class T5AgentEntitlementContextAction {

    @InvocableMethod(
        label='Get Entitlement Context for Agent'
        description='자산·계정에 연결된 서비스 계약·보증·응답목표·적용범위를 조회한다. 실 Entitlement/ServiceContract가 있으면 실값을, 없으면 데모 fallback을 반환한다.'
    )
    public static List<EntitlementOutput> getContext(List<EntitlementInput> inputs) {
        List<EntitlementOutput> results = new List<EntitlementOutput>();
        for (EntitlementInput inp : inputs) {
            results.add(execute(inp));
        }
        return results;
    }

    private static EntitlementOutput execute(EntitlementInput inp) {
        EntitlementOutput out = new EntitlementOutput();
        try {
            Id assetId = T5AgentAssetContextAction.resolveAssetIdForAgent(inp.sessionId);
            if (assetId == null) {
                return fallback(out, '자산 식별 불가 — 데모 지원 조건을 안내합니다.');
            }

            List<Asset> assets = [
                SELECT Id, Name, AccountId, Account.Name, Warranty_Type__c
                FROM Asset WHERE Id = :assetId LIMIT 1
            ];
            if (assets.isEmpty()) {
                return fallback(out, null);
            }
            Asset a = assets[0];
            out.accountName = a.Account != null ? a.Account.Name : null;

            // B 경로: 실제 서비스 계약. 활성(In Effect 또는 오늘 날짜가 기간 내)인
            // ServiceContract가 있으면 그것으로 답한다.
            List<ServiceContract> contracts = [
                SELECT Id, Name, StartDate, EndDate, ActivationDate
                FROM ServiceContract
                WHERE AccountId = :a.AccountId
                ORDER BY EndDate DESC NULLS LAST
                LIMIT 1
            ];
            // B 경로: 실제 Entitlement(자산·계정 연결).
            List<Entitlement> entitlements = [
                SELECT Id, Name, Status, StartDate, EndDate
                FROM Entitlement
                WHERE AssetId = :assetId OR AccountId = :a.AccountId
                ORDER BY EndDate DESC NULLS LAST
                LIMIT 1
            ];

            Boolean hasRealData = !contracts.isEmpty() || !entitlements.isEmpty();
            if (!hasRealData) {
                return fallback(out, null);
            }

            out.usingFallback = false;
            Date today = Date.today();

            if (!contracts.isEmpty()) {
                ServiceContract sc = contracts[0];
                Boolean active = (sc.StartDate == null || sc.StartDate <= today)
                    && (sc.EndDate == null || sc.EndDate >= today);
                out.serviceContractActive = active;
                out.serviceContractName = sc.Name;
            } else {
                out.serviceContractActive = false;
            }

            if (!entitlements.isEmpty()) {
                Entitlement e = entitlements[0];
                Boolean active = 'Active'.equalsIgnoreCase(e.Status)
                    || ((e.StartDate == null || e.StartDate <= today)
                        && (e.EndDate == null || e.EndDate >= today));
                out.warrantyActive = active;
                out.entitlementName = e.Name;
            } else {
                // Entitlement가 없으면 Asset의 보증 유형으로 보증 활성 여부만 근사.
                out.warrantyActive = String.isNotBlank(a.Warranty_Type__c);
            }

            out.warrantyType = a.Warranty_Type__c;
            out.responseTarget = '영업일 기준 4시간';
            out.coverageScope = '원격 진단 및 P3 서비스 요청 접수';
            out.billableNote = '현장 방문·부품 교체·소모품 교체는 원인과 실제 보장 조건 확인 후 적용 여부가 확정되며, 유상 가능 작업은 비용·범위 안내와 고객 승인 전에는 진행하지 않습니다.';
            out.found = true;
            return out;
        } catch (Exception ex) {
            return fallback(out, ex.getMessage());
        }
    }

    /**
     * 데모 fallback. A안에서 실 Entitlement/ServiceContract가 아직 없을 때 쓰는
     * 값이다. 프로덕션에서 레코드가 생기면 위 실 조회 경로로 자동 전환되므로
     * 이 값들은 그때 더 이상 반환되지 않는다.
     */
    private static EntitlementOutput fallback(EntitlementOutput out, String note) {
        out.found = true;
        out.usingFallback = true;
        out.serviceContractActive = true;
        out.warrantyActive = true;
        out.warrantyType = out.warrantyType != null ? out.warrantyType : '기본보증';
        out.responseTarget = '영업일 기준 4시간';
        out.coverageScope = '원격 진단 및 P3 서비스 요청 접수';
        out.billableNote = '현장 방문·부품 교체·소모품 교체는 원인과 실제 보장 조건 확인 후 적용 여부가 확정되며, 유상 가능 작업은 비용·범위 안내와 고객 승인 전에는 진행하지 않습니다.';
        if (note != null) {
            out.errorMessage = note;
        }
        return out;
    }

    public class EntitlementInput {
        @InvocableVariable(label='Session Id' description='현재 MessagingSession Id. 없으면 최근 자산 세션을 heuristic으로 찾는다.' required=false)
        public String sessionId;
    }

    public class EntitlementOutput {
        @InvocableVariable(label='Found') public Boolean found;
        @InvocableVariable(label='Using Fallback' description='true면 실 계약/보증 레코드가 없어 데모값으로 답한 것. 프로덕션 승격 시 데이터가 있으면 false가 된다.') public Boolean usingFallback;
        @InvocableVariable(label='Account Name') public String accountName;
        @InvocableVariable(label='Service Contract Active') public Boolean serviceContractActive;
        @InvocableVariable(label='Service Contract Name') public String serviceContractName;
        @InvocableVariable(label='Warranty Active') public Boolean warrantyActive;
        @InvocableVariable(label='Warranty Type') public String warrantyType;
        @InvocableVariable(label='Entitlement Name') public String entitlementName;
        @InvocableVariable(label='Response Target') public String responseTarget;
        @InvocableVariable(label='Coverage Scope') public String coverageScope;
        @InvocableVariable(label='Billable Note') public String billableNote;
        @InvocableVariable(label='Error Message') public String errorMessage;
    }
}

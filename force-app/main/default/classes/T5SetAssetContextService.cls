@RestResource(urlMapping='/T5SetAssetContext/*')
global without sharing class T5SetAssetContextService {

    // T5-23: Head Markup(top-level, LWS 밖)에서 raw fetch()로 이 REST
    // 엔드포인트를 직접 호출했더니 401 — Experience Cloud 사이트에서
    // 인증된 세션이라도 /services/apexrest/에 별도 세션 헤더 없이 fetch로
    // 붙는 건 안 먹힘(실측 확인, 2026-08-31). 그래서 표준 LWC->Apex
    // 호출 경로(@AuraEnabled, 자동으로 세션 인증됨)로 우회 — LWC가
    // localStorage에서 JWT를 직접 읽어(Storage API는 LWS 제약 밖) uid를
    // 뽑고 이 메서드를 호출한다.
    @AuraEnabled
    public static void setAssetContextFromLwc(String uid, String assetId) {
        if (String.isBlank(uid) || String.isBlank(assetId)) {
            return;
        }
        Asset_Context_Event__e evt = new Asset_Context_Event__e(
            UID__c = uid,
            Asset_Id__c = assetId
        );
        Database.SaveResult sr = EventBus.publish(evt);
        if (!sr.isSuccess()) {
            System.debug(LoggingLevel.ERROR, 'T5-23 Platform Event publish failed: ' + sr.getErrors());
        }
    }

    // T5-23: Salesforce의 Hidden Pre-Chat Field 파이프라인이 "채널 최초
    // 응대자가 Flow일 때만" 동작해서(실측 확인, 2026-08-31) 우리 채널
    // (AgentforceServiceAgent 핸들러)에서는 못 씀. 대신 브라우저 localStorage에
    // 저장된 MIAW JWT의 uid(MessagingEndUser.MessagingPlatformKey와 일치,
    // 실측 확인)를 이용해, Salesforce 내장 파이프라인을 거치지 않고 우리가
    // 직접 MessagingSession.Asset_Id__c를 채워넣는 우회 경로. Guest User
    // 프로필에서 이 클래스만 노출(Site Guest User Access 필요).
    @HttpPost
    global static void setAssetContext() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            Map<String, Object> body =
                (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
            String uid = (String) body.get('uid');
            String assetIdStr = (String) body.get('assetId');

            if (String.isBlank(uid) || String.isBlank(assetIdStr)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('{"success":false,"error":"uid and assetId are required"}');
                return;
            }

            // assetId 형식 검증(엉뚱한 값이 필드에 들어가는 걸 방지)
            try {
                Id.valueOf(assetIdStr);
            } catch (Exception e) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('{"success":false,"error":"invalid assetId"}');
                return;
            }

            // T5-23: 로그인 고객(Customer Community)도, Guest User도 라이선스
            // 자체가 MessagingSession Edit을 허용 안 함(둘 다 실측 확인,
            // 2026-08-31 — Guest는 추가로 Update 권한 자체가 플랫폼 정책상
            // 금지). @future는 호출자와 무관하게 시스템 컨텍스트로 실행되므로
            // 여기서 유효성만 검사하고 실제 조회·DML은 그쪽에 위임한다.
            applyAssetContextAsync(uid, assetIdStr);

            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"success":true}');
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('{"success":false,"error":' + JSON.serialize(e.getMessage()) + '}');
        }
    }

    @future
    global static void applyAssetContextAsync(String uid, String assetIdStr) {
        String platformKey = 'v2/iamessage/UNAUTH/NA/uid:' + uid;
        List<MessagingEndUser> endUsers = [
            SELECT Id FROM MessagingEndUser
            WHERE MessagingPlatformKey = :platformKey
            LIMIT 1
        ];
        if (endUsers.isEmpty()) {
            return;
        }

        List<MessagingSession> sessions = [
            SELECT Id FROM MessagingSession
            WHERE MessagingEndUserId = :endUsers[0].Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            return;
        }

        update new MessagingSession(Id = sessions[0].Id, Asset_Id__c = assetIdStr);
    }
}

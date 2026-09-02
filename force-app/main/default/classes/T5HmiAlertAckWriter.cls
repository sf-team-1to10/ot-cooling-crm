/**
 * `T5HmiAssetHomeController.acknowledgeAlert`가 호출자 계정 소유권 검증(해당
 * Customer_Alert__c가 호출자 Account 소유 Asset에 속하는지, WITH USER_MODE로
 * 확인)을 이미 마친 뒤에만 호출하는 좁은 시스템 컨텍스트 라이터.
 *
 * 왜 필요한가: Customer_Alert__c는 Asset의 Master-Detail 자식(ControlledByParent)
 * 이라 READ는 부모 Asset의 포털 가시성을 그대로 물려받지만, 포털 사용자가
 * Asset에 대해 갖는 접근 등급이 Read뿐이라 자식 레코드 UPDATE는
 * INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY로 막힌다(2026-08-30 확인 —
 * Asset에 Edit 객체 권한을 추가로 줘도 동일하게 막힘). Asset 자체의 Edit
 * 권한을 포털에 넓히는 대신, 이미 소유권 검증이 끝난 레코드 Id 하나·필드
 * 2개(Status__c, Acknowledged_At__c)에만 한정해서 시스템 컨텍스트로 쓴다.
 *
 * WorkOrderLineItem 우회 때 기각했던 "컨트롤러 전체를 without sharing으로
 * 열기"와는 다르다 — 인가 검사(계정 소유권 확인)는 호출자가 이미 통과했고,
 * 이 클래스는 그 결과를 실행만 한다. 이 클래스에는 다른 진입점이 없다.
 */
public without sharing class T5HmiAlertAckWriter {
    public static void write(Id alertId) {
        update new Customer_Alert__c(
            Id = alertId,
            Status__c = 'Active - Acknowledged',
            Acknowledged_At__c = Datetime.now()
        );
    }
}

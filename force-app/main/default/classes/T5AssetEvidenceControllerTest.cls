/**
 * Tests for T5AssetEvidenceController — verifies the Asset evidence timeline is
 * assembled from real records: ChangeRequest (+ related-item junction for the
 * applied point), commissioning WorkOrderLineItems (torque F-07 fail→retest,
 * flow recovery), and the header summary. Also covers missing-asset and null input.
 */
@isTest
private class T5AssetEvidenceControllerTest {

    @testSetup
    static void setup() {
        Account acct = new Account(Name = '아이온데이터 테스트');
        insert acct;

        Asset target = new Asset(
            Name = 'CDU-A-07', AccountId = acct.Id, Status = 'Installed',
            Applied_Revision__c = 'Rev.B'
        );
        Asset noHistory = new Asset(
            Name = 'CDU-A-99', AccountId = acct.Id, Status = 'Installed'
        );
        insert new List<Asset>{ target, noHistory };

        // 변경 원기록: ChangeRequest + Asset 연결 정션(적용 위치 F-07)
        // 검증 규칙: 범위 판별 후 고객 회신일·채널·요약이 있어야 진행 가능
        ChangeRequest cr = new ChangeRequest(
            Subject = 'CDU-A-07 GPU 랙 배치 변경에 따른 배관 경로 재설계',
            Revision_No__c = 'Rev.B',
            Scope_Type__c = '추가변경',
            Status = '반영완료',
            Received_Date__c = Date.newInstance(2022, 2, 17),
            Revision_Approved_Date__c = Date.newInstance(2022, 2, 21),
            Customer_Approved__c = true,
            Customer_Reply_Date__c = Date.newInstance(2022, 2, 20),
            Customer_Reply_Channel__c = '이메일',
            Customer_Reply_Summary__c = 'GPU 랙 배치 변경에 따른 배관 경로 재설계 및 비용 수락',
            Internal_Approved__c = true,
            Cost_Impact__c = 8500000,
            Schedule_Impact_Days__c = 5
        );
        insert cr;

        ChangeRequestRelatedItem link = new ChangeRequestRelatedItem(
            ChangeRequestId = cr.Id,
            AssetId = target.Id,
            RelationshipType = 'Impacted',
            Comment = '적용 위치 F-07 (DN100 · M16 × 8개소).',
            Applied_Date__c = Date.newInstance(2022, 2, 24)
        );
        insert link;

        // 시운전 WorkOrder + 측정 라인 (체결토크 F-07 68→112, 유량 1880→2100)
        WorkOrder commissionWo = new WorkOrder(
            AssetId = target.Id, Work_Subtype__c = '시운전', Status = 'New',
            Subject = 'CDU-A-07 시운전 검사',
            StartDate = Datetime.newInstance(2022, 3, 2, 0, 0, 0)
        );
        insert commissionWo;

        insert new List<WorkOrderLineItem>{
            new WorkOrderLineItem(
                WorkOrderId = commissionWo.Id, AssetId = target.Id, Line_Item_Role__c = '시험',
                Measurement_Item_Code__c = '체결토크', Measurement_Point__c = 'F-07',
                Measured_Value__c = 68, Spec_Value__c = 110, Judgement__c = '불합격', Retest_Round__c = 1
            ),
            new WorkOrderLineItem(
                WorkOrderId = commissionWo.Id, AssetId = target.Id, Line_Item_Role__c = '시험',
                Measurement_Item_Code__c = '체결토크', Measurement_Point__c = 'F-07',
                Measured_Value__c = 112, Spec_Value__c = 110, Judgement__c = '합격', Retest_Round__c = 2
            ),
            new WorkOrderLineItem(
                WorkOrderId = commissionWo.Id, AssetId = target.Id, Line_Item_Role__c = '시험',
                Measurement_Item_Code__c = '유량', Measured_Value__c = 1880, Baseline_Value__c = 2100,
                Spec_Value__c = 2050, Judgement__c = '불합격', Retest_Round__c = 1
            ),
            new WorkOrderLineItem(
                WorkOrderId = commissionWo.Id, AssetId = target.Id, Line_Item_Role__c = '시험',
                Measurement_Item_Code__c = '유량', Measured_Value__c = 2100, Spec_Value__c = 2050,
                Judgement__c = '합격', Retest_Round__c = 2
            )
        };

        insert new Case(
            Subject = 'CDU-A-07 유량 저하', Status = 'New', Priority = 'Medium',
            AccountId = acct.Id, AssetId = target.Id
        );
        insert new Case(
            Subject = 'A-99 이력 없음', Status = 'New', Priority = 'Low',
            AccountId = acct.Id, AssetId = noHistory.Id
        );
    }

    private static Id caseIdBySubject(String subject) {
        return [SELECT Id FROM Case WHERE Subject = :subject LIMIT 1].Id;
    }

    @isTest
    static void shouldBuildFullTimeline_WhenRecordsExist() {
        // Given
        Id caseId = caseIdBySubject('CDU-A-07 유량 저하');

        // When
        System.Test.startTest();
        T5AssetEvidenceController.AssetEvidence result =
            T5AssetEvidenceController.getEvidence(caseId);
        System.Test.stopTest();

        // Then — 6개 노드: chg, review, rev, commission-fail, retest, preserved
        Assert.isNotNull(result.caseNumber, 'caseNumber 반환됨');
        Assert.areEqual('CDU-A-07', result.assetName, '대상 Asset명 반환');
        Assert.areEqual(6, result.timeline.size(), 'CR 3노드 + 시운전 2노드 + 이력보존 1노드 = 6개');

        Map<String, T5AssetEvidenceController.EvidenceNode> byKey =
            new Map<String, T5AssetEvidenceController.EvidenceNode>();
        for (T5AssetEvidenceController.EvidenceNode n : result.timeline) {
            byKey.put(n.key, n);
        }
        Assert.isTrue(byKey.containsKey('chg'), 'Change Request 노드 존재');
        Assert.isTrue(byKey.containsKey('review'), '계약·기술 검토 노드 존재');
        Assert.isTrue(byKey.containsKey('rev'), 'Revision 발행 노드 존재');
        Assert.areEqual('hit', byKey.get('commission-fail').state, '최초 실패 노드 state=hit');
        Assert.areEqual('ok', byKey.get('retest').state, '재시험 노드 state=ok');
        Assert.isTrue(byKey.containsKey('preserved'), '이력 보존 결론 노드 존재');
    }

    @isTest
    static void shouldPreserveBothValues_InConclusionNode() {
        // Given
        Id caseId = caseIdBySubject('CDU-A-07 유량 저하');

        // When
        System.Test.startTest();
        T5AssetEvidenceController.AssetEvidence result =
            T5AssetEvidenceController.getEvidence(caseId);
        System.Test.stopTest();

        // Then — 이력 보존 노드는 실패값·위치·재시험값을 모두 담는다(데모 핵심 메시지)
        T5AssetEvidenceController.EvidenceNode preserved;
        for (T5AssetEvidenceController.EvidenceNode n : result.timeline) {
            if (n.key == 'preserved') {
                preserved = n;
            }
        }
        Assert.isNotNull(preserved, '이력 보존 노드 존재');
        Assert.isTrue(preserved.detail.contains('68'), '최초 실패값 68 보존');
        Assert.isTrue(preserved.detail.contains('F-07'), '변경 위치 F-07 보존');
        Assert.isTrue(preserved.detail.contains('112'), '재시험값 112 보존');
    }

    @isTest
    static void shouldExposeMeasuredValues_InTimelineText() {
        // Given
        Id caseId = caseIdBySubject('CDU-A-07 유량 저하');

        // When
        System.Test.startTest();
        T5AssetEvidenceController.AssetEvidence result =
            T5AssetEvidenceController.getEvidence(caseId);
        System.Test.stopTest();

        // Then — 실측값이 노드 텍스트에 정확히 반영
        Map<String, T5AssetEvidenceController.EvidenceNode> byKey =
            new Map<String, T5AssetEvidenceController.EvidenceNode>();
        for (T5AssetEvidenceController.EvidenceNode n : result.timeline) {
            byKey.put(n.key, n);
        }
        T5AssetEvidenceController.EvidenceNode fail = byKey.get('commission-fail');
        Assert.isTrue(fail.what.contains('68'), '최초 실패값 68 표시');
        Assert.isTrue(fail.what.contains('F-07'), '측정 위치 F-07 표시');
        Assert.isTrue(fail.detail.contains('110'), 'Spec 110 표시');
        Assert.isTrue(fail.detail.contains('1880'), '같은 시점 유량 1880 표시');

        T5AssetEvidenceController.EvidenceNode retest = byKey.get('retest');
        Assert.isTrue(retest.what.contains('112'), '재시험 합격값 112 표시');
        Assert.isTrue(retest.detail.contains('2100'), '유량 회복 2100 표시');
    }

    @isTest
    static void shouldBuildSummary_FromRealRecords() {
        // Given
        Id caseId = caseIdBySubject('CDU-A-07 유량 저하');

        // When
        System.Test.startTest();
        T5AssetEvidenceController.AssetEvidence result =
            T5AssetEvidenceController.getEvidence(caseId);
        System.Test.stopTest();

        // Then
        T5AssetEvidenceController.EvidenceSummary s = result.summary;
        Assert.isNotNull(s, '헤더 요약 존재');
        Assert.areEqual('Rev.B · F-07', s.revisionText, '적용 Revision·위치');
        Assert.areEqual('68 N·m', s.firstFailValue, '최초 실패값');
        Assert.areEqual('112 N·m', s.retestPassValue, '재시험 합격값');
    }

    @isTest
    static void shouldReturnEmptyTimeline_WhenAssetHasNoHistory() {
        // Given
        Id caseId = caseIdBySubject('A-99 이력 없음');

        // When
        System.Test.startTest();
        T5AssetEvidenceController.AssetEvidence result =
            T5AssetEvidenceController.getEvidence(caseId);
        System.Test.stopTest();

        // Then — 원기록 없으면 빈 타임라인, 요약은 '—'
        Assert.areEqual(0, result.timeline.size(), '원기록 없으면 빈 타임라인');
        Assert.areEqual('—', result.summary.revisionText, 'Revision 없음 → —');
        Assert.isNull(result.summary.firstFailValue, '실패값 없음 → null');
    }

    @isTest
    static void shouldThrowException_WhenNullCaseId() {
        // When / Then
        System.Test.startTest();
        try {
            T5AssetEvidenceController.getEvidence(null);
            Assert.fail('null Case Id는 예외를 던져야 함');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, '예외 발생 확인');
        }
        System.Test.stopTest();
    }
}

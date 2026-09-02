/**
 * Asset 이력 근거(원기록) 화면 데이터 공급 컨트롤러 (S-02, step7 v-evidence).
 * Case Id를 받아 대상 Asset의 변경·시운전 원기록을 시간순 타임라인으로 조립한다.
 * (1) ChangeRequest + ChangeRequestRelatedItem(적용 위치),
 * (2) 시운전 WorkOrder의 WorkOrderLineItem(체결토크 F-07 최초 실패→재시험, 유량 회복),
 * (3) 계약(Contract) 인수 근거.
 * 프로토타입 하드코딩을 대체해 org 실데이터로 렌더한다.
 * Callable from the otAssetEvidenceHistory LWC via @wire.
 */
public with sharing class T5AssetEvidenceController {

    private static final String ITEM_TORQUE = '체결토크';
    private static final String ITEM_FLOW = '유량';
    private static final String JUDGE_FAIL = '불합격';
    private static final String JUDGE_PASS = '합격';
    private static final String SUBTYPE_COMMISSION = '시운전';

    /**
     * 현재 Case 기준으로 Asset 원기록 타임라인을 조립한다.
     * @param caseId 조회 기준 Case Id
     * @return 헤더 요약 + 시간순 타임라인 노드를 담은 AssetEvidence
     * @throws AuraHandledException Case/Asset을 찾을 수 없을 때
     */
    @AuraEnabled(cacheable=true)
    public static AssetEvidence getEvidence(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id가 필요합니다.');
        }
        Case current = getCurrentCase(caseId);
        if (current.AssetId == null) {
            throw new AuraHandledException('Case에 연결된 Asset이 없습니다.');
        }

        AssetEvidence result = new AssetEvidence();
        result.caseNumber = current.CaseNumber;
        result.assetName = current.Asset?.Name;

        ChangeRequestRelatedItem link = getChangeRequestLink(current.AssetId);
        ChangeRequest cr = (link != null) ? getChangeRequest(link.ChangeRequestId) : null;

        List<WorkOrderLineItem> commissionLines = getCommissionLines(current.AssetId);

        result.timeline = buildTimeline(cr, link, commissionLines);
        result.summary = buildSummary(cr, link, commissionLines);
        return result;
    }

    // ─── Current Case ────────────────────────────────────────────────────

    private static Case getCurrentCase(Id caseId) {
        List<Case> cases = [
            SELECT Id, CaseNumber, AssetId, Asset.Name
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            throw new AuraHandledException('Case를 찾을 수 없습니다: ' + caseId);
        }
        return cases[0];
    }

    // ─── ChangeRequest (변경 원기록) ───────────────────────────────────────

    /**
     * 대상 Asset에 연결된 ChangeRequestRelatedItem(정션)을 가져온다.
     * 적용 위치(Comment)와 적용일(Applied_Date__c)을 함께 확보한다.
     */
    private static ChangeRequestRelatedItem getChangeRequestLink(Id assetId) {
        List<ChangeRequestRelatedItem> links = [
            SELECT Id, ChangeRequestId, AssetId, Comment, ImpactLevel, Applied_Date__c
            FROM ChangeRequestRelatedItem
            WHERE AssetId = :assetId
            WITH USER_MODE
            ORDER BY Applied_Date__c ASC NULLS LAST
            LIMIT 1
        ];
        return links.isEmpty() ? null : links[0];
    }

    private static ChangeRequest getChangeRequest(Id changeRequestId) {
        List<ChangeRequest> crs = [
            SELECT Id, ChangeRequestNumber, Subject, Revision_No__c, Scope_Type__c,
                   Status, Received_Date__c, Revision_Approved_Date__c,
                   Customer_Approved__c, Cost_Impact__c, Schedule_Impact_Days__c,
                   Technical_Impact__c, Requester__r.Name, Revision_Approver__r.Name
            FROM ChangeRequest
            WHERE Id = :changeRequestId
            WITH USER_MODE
            LIMIT 1
        ];
        return crs.isEmpty() ? null : crs[0];
    }

    // ─── 시운전 WOLI (체결토크·유량 원기록) ─────────────────────────────────

    /**
     * 대상 Asset의 시운전 WorkOrder에 속한 측정 라인을 시간순으로 가져온다.
     * 체결토크(F-07)와 유량의 최초/재시험 값을 화면에서 선별한다.
     */
    private static List<WorkOrderLineItem> getCommissionLines(Id assetId) {
        return [
            SELECT Id, Measurement_Item_Code__c, Measurement_Point__c,
                   Measured_Value__c, Baseline_Value__c, Spec_Value__c,
                   Judgement__c, Retest_Round__c, Line_Item_Role__c,
                   Verified_By__r.Name,
                   WorkOrder.StartDate, WorkOrder.WorkOrderNumber
            FROM WorkOrderLineItem
            WHERE WorkOrder.AssetId = :assetId
              AND WorkOrder.Work_Subtype__c = :SUBTYPE_COMMISSION
              AND Measured_Value__c != null
            WITH USER_MODE
            ORDER BY Retest_Round__c ASC
        ];
    }

    // ─── 타임라인 조립 ─────────────────────────────────────────────────────

    /**
     * CR·정션·시운전 측정에서 시간순 타임라인 노드를 만든다.
     * 각 노드는 실제 레코드가 있을 때만 추가한다(없으면 생략 → 화면 degrade).
     */
    private static List<EvidenceNode> buildTimeline(
        ChangeRequest cr,
        ChangeRequestRelatedItem link,
        List<WorkOrderLineItem> commissionLines
    ) {
        List<EvidenceNode> nodes = new List<EvidenceNode>();

        // 1) Change Request 접수
        if (cr != null) {
            EvidenceNode n = new EvidenceNode();
            n.key = 'chg';
            n.state = '';
            n.whenText = formatDate(cr.Received_Date__c) + ' · Change Request';
            n.what = cr.Subject;
            n.detail = '설치 진행 중 접수된 변경 요청입니다.';
            String requester = cr.Requester__r != null ? cr.Requester__r.Name : null;
            n.source = cr.ChangeRequestNumber
                + (String.isNotBlank(requester) ? ' · 요청자 ' + requester : '');
            nodes.add(n);

            // 2) 계약·기술 검토 (CR의 Scope/Impact 필드에서 도출)
            if (String.isNotBlank(cr.Scope_Type__c)) {
                EvidenceNode n2 = new EvidenceNode();
                n2.key = 'review';
                n2.state = '';
                n2.whenText = '계약·기술 검토';
                n2.what = cr.Scope_Type__c + '으로 판정';
                n2.detail = buildReviewDetail(cr);
                n2.source = String.isNotBlank(cr.Technical_Impact__c)
                    ? cr.Technical_Impact__c
                    : cr.ChangeRequestNumber + ' 검토';
                nodes.add(n2);
            }

            // 3) Revision 발행
            if (cr.Revision_Approved_Date__c != null && String.isNotBlank(cr.Revision_No__c)) {
                EvidenceNode n3 = new EvidenceNode();
                n3.key = 'rev';
                n3.state = '';
                n3.whenText = formatDate(cr.Revision_Approved_Date__c) + ' · Revision 발행';
                String point = (link != null && String.isNotBlank(link.Comment)) ? link.Comment : null;
                n3.what = cr.Revision_No__c + ' 승인'
                    + (point != null ? ' · 적용 위치 확인' : '');
                n3.detail = '설계 검토와 고객 승인을 거쳐 ' + cr.Revision_No__c + '가 발행됐습니다.'
                    + (cr.Customer_Approved__c == true ? ' 고객 승인 완료.' : '')
                    + (point != null ? ' ' + point : '');
                String approver = cr.Revision_Approver__r != null ? cr.Revision_Approver__r.Name : null;
                n3.source = cr.Revision_No__c
                    + (String.isNotBlank(approver) ? ' · 승인자 ' + approver : '')
                    + (link != null && link.Applied_Date__c != null
                        ? ' · 적용 ' + formatDate(link.Applied_Date__c) : '');
                nodes.add(n3);
            }
        }

        // 4~5) 시운전 측정 — 항목별 최초/재시험
        addCommissionNodes(nodes, commissionLines);

        return nodes;
    }

    /**
     * 시운전 측정 라인을 항목(체결토크/유량)별로 묶어 최초·재시험 노드를 만든다.
     */
    private static void addCommissionNodes(List<EvidenceNode> nodes, List<WorkOrderLineItem> commissionLines) {
        WorkOrderLineItem torqueFail;
        WorkOrderLineItem torquePass;
        WorkOrderLineItem flowFail;
        WorkOrderLineItem flowPass;
        Date commissionDate;

        for (WorkOrderLineItem w : commissionLines) {
            if (w.WorkOrder != null && w.WorkOrder.StartDate != null && commissionDate == null) {
                commissionDate = w.WorkOrder.StartDate.date();
            }
            if (w.Measurement_Item_Code__c == ITEM_TORQUE) {
                if (w.Judgement__c == JUDGE_FAIL && torqueFail == null) {
                    torqueFail = w;
                } else if (w.Judgement__c == JUDGE_PASS && torquePass == null) {
                    torquePass = w;
                }
            } else if (w.Measurement_Item_Code__c == ITEM_FLOW) {
                if (w.Judgement__c == JUDGE_FAIL && flowFail == null) {
                    flowFail = w;
                } else if (w.Judgement__c == JUDGE_PASS && flowPass == null) {
                    flowPass = w;
                }
            }
        }

        String dateLabel = (commissionDate != null) ? formatDate(commissionDate) : '시운전';

        // 4) 최초 검사 — 체결토크 불합격
        if (torqueFail != null) {
            EvidenceNode n = new EvidenceNode();
            n.key = 'commission-fail';
            n.state = 'hit';
            n.whenText = dateLabel + ' · 시운전 최초 검사';
            String point = String.isNotBlank(torqueFail.Measurement_Point__c)
                ? torqueFail.Measurement_Point__c + ' ' : '';
            n.what = point + '체결값 ' + formatNum(torqueFail.Measured_Value__c) + ' N·m — 기준 미달';
            n.detail = '설계 목표 ' + formatNum(torqueFail.Spec_Value__c) + ' N·m.'
                + ' 최초 검사에서 기준에 미달했습니다.'
                + (flowFail != null
                    ? ' 같은 시점 유량은 ' + formatNum(flowFail.Measured_Value__c) + ' L/min이었습니다.'
                    : '');
            n.source = '시운전 WO · 측정' + verifierSuffix(torqueFail);
            nodes.add(n);
        }

        // 5) 재조임 후 재시험 — 체결토크 합격 + 유량 회복
        if (torquePass != null) {
            EvidenceNode n = new EvidenceNode();
            n.key = 'retest';
            n.state = 'ok';
            n.whenText = dateLabel + ' · 재조임 후 재시험';
            n.what = '체결값 ' + formatNum(torquePass.Measured_Value__c) + ' N·m'
                + (flowPass != null ? ' · 유량 ' + formatNum(flowPass.Measured_Value__c) + ' L/min' : '');
            n.detail = '재조임 후 정상화됐습니다.'
                + (flowFail != null && flowPass != null
                    ? ' 유량도 ' + formatNum(flowFail.Measured_Value__c) + ' → '
                        + formatNum(flowPass.Measured_Value__c) + '으로 회복됐습니다.'
                    : '')
                + ' 당시에는 해결된 문제였습니다.';
            n.source = '재시험 WOLI · 판정 합격' + verifierSuffix(torquePass);
            nodes.add(n);
        }

        // 6) 이력 보존 — 최초 실패값과 재시험 합격값이 같은 장비에 함께 남았다는 결론.
        // 별도 인수 레코드가 아니라, 68(불합격)·112(합격) 두 측정이 org에 공존한다는
        // 사실 자체가 근거다. 데모 핵심 메시지("합격값만 남기지 않았다")를 이 노드가 담는다.
        if (torqueFail != null && torquePass != null) {
            EvidenceNode n = new EvidenceNode();
            n.key = 'preserved';
            n.state = 'ok';
            String point = String.isNotBlank(torqueFail.Measurement_Point__c)
                ? torqueFail.Measurement_Point__c : 'F-07';
            n.whenText = '이력 보존';
            n.what = '최종 합격값만 남기지 않았습니다';
            n.detail = '최초 실패값 ' + formatNum(torqueFail.Measured_Value__c)
                + ', 변경 위치 ' + point
                + ', 재시험값 ' + formatNum(torquePass.Measured_Value__c)
                + '를 같은 장비의 이력으로 남겼습니다.'
                + ' 이 기록이 4년 뒤 오늘의 점검 위치를 좁혔습니다.';
            n.source = '시운전 WO · 실패/재시험 측정 공존';
            nodes.add(n);
        }
    }

    private static String buildReviewDetail(ChangeRequest cr) {
        List<String> parts = new List<String>();
        if (cr.Cost_Impact__c != null) {
            parts.add('비용 영향 ' + formatNum(cr.Cost_Impact__c) + '원');
        }
        if (cr.Schedule_Impact_Days__c != null) {
            parts.add('일정 영향 ' + formatNum(cr.Schedule_Impact_Days__c) + '일');
        }
        String base = '계약 특약과 기술 전제를 확인해 별도 검토가 필요한 변경으로 판단했습니다.';
        return parts.isEmpty() ? base : base + ' (' + String.join(parts, ' · ') + ')';
    }

    /**
     * 측정 라인의 검증자(검사자) 이름을 " · 검사자 {이름}" 접미사로 만든다. 없으면 빈 문자열.
     */
    private static String verifierSuffix(WorkOrderLineItem line) {
        if (line != null && line.Verified_By__r != null && String.isNotBlank(line.Verified_By__r.Name)) {
            return ' · 검사자 ' + line.Verified_By__r.Name;
        }
        return '';
    }

    // ─── 헤더 요약 ─────────────────────────────────────────────────────────

    /**
     * 헤더 하이라이트 필드(적용 Revision·위치, 최초 실패값, 재시험 합격값, 원기록 건수)를 조립한다.
     */
    private static EvidenceSummary buildSummary(
        ChangeRequest cr,
        ChangeRequestRelatedItem link,
        List<WorkOrderLineItem> commissionLines
    ) {
        EvidenceSummary s = new EvidenceSummary();
        s.revisionText = (cr != null && String.isNotBlank(cr.Revision_No__c))
            ? cr.Revision_No__c : '—';

        String point = null;
        for (WorkOrderLineItem w : commissionLines) {
            if (w.Measurement_Item_Code__c == ITEM_TORQUE
                && String.isNotBlank(w.Measurement_Point__c)) {
                point = w.Measurement_Point__c;
                break;
            }
        }
        if (point != null) {
            s.revisionText += ' · ' + point;
        }

        for (WorkOrderLineItem w : commissionLines) {
            if (w.Measurement_Item_Code__c == ITEM_TORQUE) {
                if (w.Judgement__c == JUDGE_FAIL && s.firstFailValue == null) {
                    s.firstFailValue = formatNum(w.Measured_Value__c) + ' N·m';
                } else if (w.Judgement__c == JUDGE_PASS && s.retestPassValue == null) {
                    s.retestPassValue = formatNum(w.Measured_Value__c) + ' N·m';
                }
            }
        }
        return s;
    }

    // ─── 포맷 헬퍼 ─────────────────────────────────────────────────────────

    private static String formatDate(Date d) {
        if (d == null) {
            return '';
        }
        return d.year() + '-' + twoDigit(d.month()) + '-' + twoDigit(d.day());
    }

    private static String twoDigit(Integer n) {
        return (n < 10 ? '0' : '') + String.valueOf(n);
    }

    private static String formatNum(Decimal value) {
        if (value == null) {
            return '—';
        }
        // 정수면 소수점 제거, 아니면 그대로
        if (value == value.round()) {
            return String.valueOf(value.longValue());
        }
        return String.valueOf(value);
    }

    // ─── DTOs ────────────────────────────────────────────────────────────

    public class AssetEvidence {
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String assetName;
        @AuraEnabled public EvidenceSummary summary;
        @AuraEnabled public List<EvidenceNode> timeline = new List<EvidenceNode>();
    }

    public class EvidenceSummary {
        @AuraEnabled public String revisionText;
        @AuraEnabled public String firstFailValue;
        @AuraEnabled public String retestPassValue;
    }

    public class EvidenceNode {
        @AuraEnabled public String key;
        @AuraEnabled public String state;
        @AuraEnabled public String whenText;
        @AuraEnabled public String what;
        @AuraEnabled public String detail;
        @AuraEnabled public String source;
    }
}
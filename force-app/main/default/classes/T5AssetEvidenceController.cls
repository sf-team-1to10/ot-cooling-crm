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
    private static final String SUBTYPE_RECOVERY = '장애복구';

    /**
     * 현재 Case 기준으로 Asset 원기록 타임라인을 조립한다.
     * @param caseId 조회 기준 Case Id
     * @return 헤더 요약 + 시간순 타임라인 노드를 담은 AssetEvidence
     * @throws AuraHandledException Case/Asset을 찾을 수 없을 때
     */
    @AuraEnabled(cacheable=true)
    public static AssetEvidence getEvidence(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('레코드 Id가 필요합니다.');
        }
        // 파라미터가 WorkOrder Id로 들어오면 CaseId로 해석
        Id resolvedCaseId = resolveCaseId(caseId);
        Case current = getCurrentCase(resolvedCaseId);
        if (current.AssetId == null) {
            throw new AuraHandledException('Case에 연결된 Asset이 없습니다.');
        }

        AssetEvidence result = new AssetEvidence();
        result.caseNumber = current.CaseNumber;
        result.assetName = current.Asset?.Name;

        ChangeRequestRelatedItem link = getChangeRequestLink(current.AssetId);
        ChangeRequest cr = (link != null) ? getChangeRequest(link.ChangeRequestId) : null;

        List<WorkOrderLineItem> commissionLines = getCommissionLines(current.AssetId);
        List<WorkOrderLineItem> recoveryLines = getRecoveryLines(current.AssetId);

        result.timeline = buildTimeline(cr, link, commissionLines);
        result.summary = buildSummary(cr, link, commissionLines);
        result.recovery = buildRecovery(recoveryLines);
        return result;
    }

    // ─── Current Case ────────────────────────────────────────────────────

    /**
     * 파라미터 Id의 sobject prefix에 따라 실제 Case Id로 정규화한다.
     * - `500` 접두어(Case) → 그대로 반환
     * - `0WO` 접두어(WorkOrder) → 해당 WO의 CaseId 조회
     * 기타 오브젝트가 들어오면 예외를 던진다.
     */
    private static Id resolveCaseId(Id recordId) {
        String prefix = String.valueOf(recordId).substring(0, 3);
        if (prefix == '500') {
            return recordId;
        }
        if (prefix == '0WO') {
            List<WorkOrder> wos = [
                SELECT CaseId
                FROM WorkOrder
                WHERE Id = :recordId
                WITH USER_MODE
                LIMIT 1
            ];
            if (wos.isEmpty() || wos[0].CaseId == null) {
                throw new AuraHandledException('WorkOrder에 연결된 Case가 없습니다.');
            }
            return wos[0].CaseId;
        }
        throw new AuraHandledException('지원하지 않는 레코드 유형입니다: ' + prefix);
    }

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

    /**
     * 대상 Asset의 장애복구 WorkOrder에 속한 측정 라인을 가져온다.
     * 2026년 현장 조치의 전/후 값(체결토크·유량)을 카드로 노출한다.
     */
    private static List<WorkOrderLineItem> getRecoveryLines(Id assetId) {
        return [
            SELECT Id, Measurement_Item_Code__c, Measurement_Point__c,
                   Measured_Value__c, Spec_Value__c, Judgement__c,
                   WorkOrder.StartDate, WorkOrder.EndDate,
                   WorkOrder.WorkOrderNumber, WorkOrder.Case.CaseNumber
            FROM WorkOrderLineItem
            WHERE WorkOrder.AssetId = :assetId
              AND WorkOrder.Work_Subtype__c = :SUBTYPE_RECOVERY
              AND Measured_Value__c != null
            WITH USER_MODE
            ORDER BY WorkOrder.StartDate DESC
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
            n.whenText = formatDate(cr.Received_Date__c) + ' · Change Request 접수';
            n.what = cr.Subject;
            n.detail = '설치 진행 중 고객 요청으로 변경 검토 개시';
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
                n2.what = cr.Scope_Type__c + ' 판정';
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
                    + (point != null ? ' · ' + point + ' 적용' : '');
                List<String> parts = new List<String>();
                parts.add('설계 검토 · 고객 승인 완료');
                if (cr.Customer_Approved__c == true) {
                    // 고객 승인 표시는 이미 위 문구에 포함
                }
                n3.detail = String.join(parts, ' · ');
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
            n.what = point + '체결토크 ' + formatNum(torqueFail.Measured_Value__c) + ' N·m 불합격';
            List<String> parts = new List<String>();
            parts.add('설계 Spec ' + formatNum(torqueFail.Spec_Value__c) + ' N·m 대비 미달');
            if (flowFail != null) {
                parts.add('동시 측정 유량 ' + formatNum(flowFail.Measured_Value__c) + ' L/min');
            }
            n.detail = String.join(parts, ' · ');
            n.source = '시운전 WO · 최초 측정' + verifierSuffix(torqueFail);
            nodes.add(n);
        }

        // 5) 재조임 후 재시험 — 체결토크 합격 + 유량 회복
        if (torquePass != null) {
            EvidenceNode n = new EvidenceNode();
            n.key = 'retest';
            n.state = 'ok';
            n.whenText = dateLabel + ' · 재조임 후 재시험';
            n.what = '체결토크 ' + formatNum(torquePass.Measured_Value__c) + ' N·m 합격'
                + (flowPass != null ? ' · 유량 ' + formatNum(flowPass.Measured_Value__c) + ' L/min 회복' : '');
            List<String> parts = new List<String>();
            parts.add('재조임 후 규격 범위 내로 복원');
            if (flowFail != null && flowPass != null) {
                parts.add('유량 ' + formatNum(flowFail.Measured_Value__c)
                    + ' → ' + formatNum(flowPass.Measured_Value__c) + ' L/min');
            }
            n.detail = String.join(parts, ' · ');
            n.source = '시운전 WO · 재시험 판정' + verifierSuffix(torquePass);
            nodes.add(n);
        }

        // 6) 이력 보존 — 실패·합격 측정이 함께 남았다는 사실을 시간축의 마지막 노드로 기록.
        if (torqueFail != null && torquePass != null) {
            EvidenceNode n = new EvidenceNode();
            n.key = 'preserved';
            n.state = 'ok';
            String point = String.isNotBlank(torqueFail.Measurement_Point__c)
                ? torqueFail.Measurement_Point__c : 'F-07';
            n.whenText = dateLabel + ' · 원기록 확정';
            n.what = point + ' 불합격/합격 측정 이력 병존';
            n.detail = '불합격 ' + formatNum(torqueFail.Measured_Value__c)
                + ' N·m · 합격 ' + formatNum(torquePass.Measured_Value__c)
                + ' N·m 두 판정이 같은 Asset 이력에 보존됨';
            n.source = '시운전 WO · WOLI 2건';
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

    /**
     * WO의 원인·근거 확인 결과를 Problem으로 승격한다.
     * 데모 시나리오상 같은 Case에 대해 여러 번 생성되지 않도록,
     * CaseRelatedIssue 정션으로 이미 연결된 Problem이 있으면 그 Id를 반환한다.
     * 없으면 새로 만들어 Case와 연결한 뒤 Id를 반환한다.
     * @param recordId Case Id
     */
    @AuraEnabled
    public static Id createProblemWithRca(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('레코드 Id가 필요합니다.');
        }
        Id caseId = resolveCaseId(recordId);
        Case current = getCurrentCase(caseId);

        // 이미 연결된 Problem이 있으면 재사용
        List<CaseRelatedIssue> existing = [
            SELECT RelatedIssueId
            FROM CaseRelatedIssue
            WHERE CaseId = :caseId
              AND RelatedIssueId != null
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].RelatedIssueId;
        }

        String subject = (current.Asset != null && String.isNotBlank(current.Asset.Name))
            ? current.Asset.Name + ' 원인 확정 · RCA 초안'
            : 'RCA 초안';
        Problem p = new Problem(
            Subject = subject,
            Description = current.CaseNumber != null
                ? 'Case ' + current.CaseNumber + '의 현장 조치 결과 기반 근본원인 분석 초안입니다.'
                : '현장 조치 결과 기반 근본원인 분석 초안입니다.'
        );
        insert as user p;

        CaseRelatedIssue link = new CaseRelatedIssue(
            CaseId = caseId,
            RelatedIssueId = p.Id
        );
        insert as user link;

        return p.Id;
    }

    // ─── 오늘의 측정 요약 (2026 장애복구 WO) ─────────────────────────────
    /**
     * 장애복구 WO의 최신 측정 라인에서 조치 전(불합격) 토크, 조치 후(합격) 토크,
     * 조치 후 유량 세 값을 뽑아 카드용 요약 DTO를 만든다.
     */
    private static RecoverySummary buildRecovery(List<WorkOrderLineItem> lines) {
        RecoverySummary r = new RecoverySummary();
        if (lines == null || lines.isEmpty()) {
            return r;
        }
        Date recoveryDate;
        Datetime endDt;
        for (WorkOrderLineItem w : lines) {
            if (w.WorkOrder != null && w.WorkOrder.StartDate != null && recoveryDate == null) {
                recoveryDate = w.WorkOrder.StartDate.date();
                r.woNumber = w.WorkOrder.WorkOrderNumber;
                if (w.WorkOrder.EndDate != null) {
                    endDt = w.WorkOrder.EndDate;
                }
                if (w.WorkOrder.Case != null && String.isNotBlank(w.WorkOrder.Case.CaseNumber)) {
                    r.caseNumber = w.WorkOrder.Case.CaseNumber;
                }
            }
            if (w.Measurement_Item_Code__c == ITEM_TORQUE) {
                if (String.isBlank(r.measurementPoint) && String.isNotBlank(w.Measurement_Point__c)) {
                    r.measurementPoint = w.Measurement_Point__c;
                }
                if (w.Judgement__c == JUDGE_FAIL && r.torqueBefore == null) {
                    r.torqueBefore = formatNum(w.Measured_Value__c);
                } else if (w.Judgement__c == JUDGE_PASS && r.torqueAfter == null) {
                    r.torqueAfter = formatNum(w.Measured_Value__c);
                }
            } else if (w.Measurement_Item_Code__c == ITEM_FLOW) {
                if (w.Judgement__c == JUDGE_PASS && r.flowAfter == null) {
                    r.flowAfter = formatNum(w.Measured_Value__c);
                }
            }
        }
        r.recoveryDateText = (recoveryDate != null) ? formatDate(recoveryDate) : '';
        r.completedAtText = (endDt != null) ? formatDateTimeShort(endDt) : '';
        r.hasData = r.torqueBefore != null || r.torqueAfter != null || r.flowAfter != null;
        return r;
    }

    /**
     * "MM-dd HH:mm" 형태로 포맷 (연도 생략, 시각 표시).
     * WO EndDate 헤더 표기용.
     */
    private static String formatDateTimeShort(Datetime dt) {
        return twoDigit(dt.month()) + '-' + twoDigit(dt.day())
             + ' ' + twoDigit(dt.hour()) + ':' + twoDigit(dt.minute());
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
        @AuraEnabled public RecoverySummary recovery;
    }

    public class EvidenceSummary {
        @AuraEnabled public String revisionText;
        @AuraEnabled public String firstFailValue;
        @AuraEnabled public String retestPassValue;
    }

    public class RecoverySummary {
        @AuraEnabled public Boolean hasData = false;
        @AuraEnabled public String woNumber;
        @AuraEnabled public String recoveryDateText;
        @AuraEnabled public String torqueBefore;
        @AuraEnabled public String torqueAfter;
        @AuraEnabled public String flowAfter;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String measurementPoint;
        @AuraEnabled public String completedAtText;
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
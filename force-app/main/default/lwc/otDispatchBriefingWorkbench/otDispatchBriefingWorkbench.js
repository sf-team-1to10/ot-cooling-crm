import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon
} from 'lightning/platformWorkspaceApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { updateRecord } from 'lightning/uiRecordApi';
import CASE_ID from '@salesforce/schema/Case.Id';
import CASE_STAGE from '@salesforce/schema/Case.Stage__c';
import getBriefing from '@salesforce/apex/T5DispatchBriefingController.getBriefing';

export default class OtDispatchBriefingWorkbench extends LightningElement {
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    // 최초 진입 상태 — false면 안내 + 브리핑 생성 버튼만 렌더
    briefingRevealed = false;

    // Slack 전문가 소집 Flow 모달 상태
    showSwarmFlow = false;
    swarmFlowLoaded = false;

    get swarmFlowLoading() {
        return !this.swarmFlowLoaded;
    }

    get swarmCardClass() {
        return this.swarmFlowLoaded ? 'swarm-card' : 'swarm-card swarm-card_hidden';
    }

    get swarmFlowInputVariables() {
        return [{ name: 'recordId', type: 'String', value: this.effectiveRecordId }];
    }

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        const stateId = pageRef?.state?.c__recordId || pageRef?.attributes?.recordId;
        if (stateId) {
            this._stateRecordId = stateId;
        }
    }

    @wire(EnclosingTabId)
    setTabId(tabId) {
        this._tabId = tabId;
        this.labelEnclosingTab();
    }

    async labelEnclosingTab() {
        if (this._tabLabeled || !this._tabId) {
            return;
        }
        this._tabLabeled = true;
        try {
            await setTabLabel(this._tabId, '출동 준비');
            await setTabIcon(this._tabId, 'standard:case');
        } catch (e) { /* 콘솔 외 컨텍스트 무시 */ }
    }

    get effectiveRecordId() {
        return this.recordId || this._stateRecordId || undefined;
    }

    briefing;
    error;

    @wire(getBriefing, { caseId: '$effectiveRecordId' })
    wiredBriefing({ data, error }) {
        if (data) {
            this.briefing = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.briefing = undefined;
        }
    }

    get isLoading() {
        return this.briefingRevealed && !this.briefing && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || '브리핑 데이터를 불러오지 못했습니다.';
    }

    get showIntake() {
        return !this.briefingRevealed;
    }

    get showBriefing() {
        return this.briefingRevealed && this.briefing;
    }

    get slaRemaining() {
        return this.briefing?.slaRemaining || '—';
    }

    get calculatedAtText() {
        return this.formatTime(this.briefing?.calculatedAt);
    }

    formatTime(raw) {
        if (!raw) {
            return '—';
        }
        return new Date(raw).toLocaleTimeString('ko-KR', {
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    // ─── 액션 핸들러 ───

    // 최초 진입에서 "출동 브리핑 생성" 클릭 → 본문 렌더 + Stage "1 진단·브리핑"
    async handleGenerateBriefing() {
        this.briefingRevealed = true;
        await this.updateCaseStage('1 진단·브리핑');
    }

    // Slack 전문가 소집 Flow 모달 실행 + Stage "2 담당자 배정"
    async handleSlack() {
        if (!this.effectiveRecordId) {
            return;
        }
        this.swarmFlowLoaded = false;
        this.showSwarmFlow = true;
        await this.updateCaseStage('2 담당자 배정');
    }

    closeSwarmFlow() {
        this.showSwarmFlow = false;
        this.swarmFlowLoaded = false;
    }

    handleSwarmOverlayClick() {
        this.closeSwarmFlow();
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    handleSwarmStatusChange(event) {
        const status = event.detail.status;
        if (status !== 'ERROR') {
            this.swarmFlowLoaded = true;
        }
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            this.showSwarmFlow = false;
            this.swarmFlowLoaded = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Slack 전문가 소집 완료',
                    message: 'Slack 채널이 생성되고 전문가에게 Case 요약이 발신됐습니다.',
                    variant: 'success'
                })
            );
        }
    }

    // "출동 확정" 클릭 → Toast + Stage "3 현장 출동"
    async handleDispatchConfirm() {
        await this.updateCaseStage('3 현장 출동');
        this.dispatchEvent(
            new ShowToastEvent({
                title: '강시공 배정 완료',
                message: 'Slack Swarm에서 강시공이 현장 출동으로 배정됐습니다. Work Order가 생성됩니다.',
                variant: 'success'
            })
        );
    }

    async updateCaseStage(stageValue) {
        const caseId = this.effectiveRecordId;
        if (!caseId) return;
        const fields = {};
        fields[CASE_ID.fieldApiName] = caseId;
        fields[CASE_STAGE.fieldApiName] = stageValue;
        try {
            await updateRecord({ fields });
        } catch (e) {
            // 이미 같은 값이면 무시. 실패 시엔 조용히 넘어감(데모 단계이므로).
        }
    }

    // ─── 브리핑 본문 뷰 게터 ───

    get rationale() {
        return this.briefing?.priorityRationale;
    }

    get rationaleFactors() {
        const factors = this.rationale?.factors || [];
        return factors.map((f) => ({
            ...f,
            valueText: f.available ? f.value : '—',
            contributionText: f.available ? f.contribution : '준비중',
            contributionClass: f.available
                ? this.contributionChipClass(f.contribution)
                : 'chip'
        }));
    }

    contributionChipClass(contribution) {
        if (contribution === '높음') {
            return 'chip chip--neg';
        }
        if (contribution === '보통') {
            return 'chip chip--warn';
        }
        return 'chip chip--info';
    }

    get comparisonRows() {
        const rows = this.briefing?.comparisons || [];
        const targetName = this.briefing?.targetAssetName;
        return rows.map((c) => {
            const isTarget = c.assetName === targetName;
            const hasTrendChip = c.trendFlag === '이상' || c.trendFlag === '주의';
            return {
                ...c,
                key: c.assetId,
                isTarget,
                driftText: c.driftFromBaseline == null ? '—' : `${c.driftFromBaseline}%`,
                measuredText: c.measuredValue == null ? '—' : `${c.measuredValue} L/min`,
                revisionText: c.appliedRevision || '—',
                rowClass: isTarget ? 'cmp-row cmp-row--target' : 'cmp-row',
                hasTrendChip,
                trendClass: hasTrendChip ? this.trendChipClass(c.trendFlag) : '',
                pastFailureText: c.hasPastFailure ? '있음' : '—'
            };
        });
    }

    trendChipClass(trend) {
        if (trend === '이상') {
            return 'chip chip--neg';
        }
        return 'chip chip--warn';
    }

    get hasComparisons() {
        return (this.briefing?.comparisons || []).length > 0;
    }

    get similarCaseInsights() {
        return this.toInsights(this.briefing?.similarCasesSummary);
    }

    get briefingInsights() {
        return this.toInsights(this.briefing?.briefingBody);
    }

    get hasSimilarCaseInsights() {
        return this.similarCaseInsights.length > 0;
    }

    get hasBriefingInsights() {
        return this.briefingInsights.length > 0;
    }

    // '■ 라벨 본문...' 문자열을 { label, body } 리스트로 파싱.
    // 라벨은 첫 어절(공백 기준 2~3 단어 히어리스틱)로 뽑고, 나머지는 본문으로.
    toInsights(raw) {
        if (!raw) return [];
        return raw
            .split('■')
            .map((seg) => seg.trim())
            .filter((seg) => seg.length > 0)
            .map((seg, i) => {
                const { label, body } = this.splitLabel(seg);
                return { key: `insight-${i}`, label, body };
            });
    }

    splitLabel(seg) {
        // 알려진 라벨 후보 우선 매칭 (데이터가 일정한 패턴을 따를 때 정확도↑)
        const KNOWN_LABELS = [
            '원인 분포', '평균 복구시간', '재발 판정 근거',
            '우선 점검 후보', '핵심 근거', '주의 신호', '권장 조치'
        ];
        for (const l of KNOWN_LABELS) {
            if (seg.startsWith(l)) {
                return { label: l, body: seg.slice(l.length).trim() };
            }
        }
        // fallback: 앞 2어절을 라벨로
        const tokens = seg.split(/\s+/);
        if (tokens.length <= 2) return { label: '', body: seg };
        return { label: tokens.slice(0, 2).join(' '), body: tokens.slice(2).join(' ') };
    }
}

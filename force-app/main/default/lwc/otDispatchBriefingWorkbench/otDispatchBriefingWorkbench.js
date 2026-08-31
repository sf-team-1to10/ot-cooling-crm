import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon,
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    focusTab
} from 'lightning/platformWorkspaceApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getBriefing from '@salesforce/apex/T5DispatchBriefingController.getBriefing';
import approveDispatch from '@salesforce/apex/T5DispatchBriefingController.approveDispatch';

export default class OtDispatchBriefingWorkbench extends NavigationMixin(LightningElement) {
    // Record page에서는 자동 주입, App Page에서는 pageReference state에서 해석한다.
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    // Slack 전문가 소집 Flow 모달 상태
    showSwarmFlow = false;
    swarmFlowLoaded = false;

    get swarmFlowLoading() {
        return !this.swarmFlowLoaded;
    }

    get swarmCardClass() {
        return this.swarmFlowLoaded ? 'swarm-card' : 'swarm-card swarm-card_hidden';
    }

    // Flow input: 전문가 소집 Flow는 recordId(Case Id)를 받는다.
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

    @wire(IsConsoleNavigation) isConsoleNavigation;

    get isConsole() {
        return this.isConsoleNavigation?.data === true;
    }

    // EnclosingTabId wire는 탭 컨텍스트가 준비된 후에 tabId를 반응형으로 준다.
    // standard__component 서브탭은 컴포넌트 로드 완료 시 라벨을 'Loading...'으로 덮으므로,
    // 이 wire(=로드 후)로 tabId를 받아 라벨을 다시 설정해야 최종적으로 고정된다.
    @wire(EnclosingTabId)
    setTabId(tabId) {
        this._tabId = tabId;
        this.labelEnclosingTab();
    }

    async labelEnclosingTab() {
        if (this._tabLabeled || !this._tabId || !this.caseNumber) {
            return;
        }
        this._tabLabeled = true;
        await setTabLabel(this._tabId, `${this.caseNumber} 출동 브리핑`);
        // standard: 계열 아이콘은 콘솔 탭에서 다른 탭(Case 등)과 동일한 크기로 렌더된다.
        // utility: 계열은 크게 나와 옆 탭 아이콘과 크기가 안 맞는다.
        await setTabIcon(this._tabId, 'standard:announcement');
    }

    get effectiveRecordId() {
        // undefined를 반환해야 wire가 실행되지 않는다(null이면 Apex가 예외를 던짐).
        return this.recordId || this._stateRecordId || undefined;
    }

    briefing;
    error;
    _wiredBriefing;

    @wire(getBriefing, { caseId: '$effectiveRecordId' })
    wiredBriefing(response) {
        this._wiredBriefing = response;
        const { data, error } = response;
        if (data) {
            this.briefing = data;
            this.error = undefined;
            // caseNumber 확보 — tabId가 이미 왔다면 이 시점에 라벨을 설정한다.
            this.labelEnclosingTab();
        } else if (error) {
            this.error = error;
            this.briefing = undefined;
        }
    }

    get isLoading() {
        return !this.briefing && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || '브리핑 데이터를 불러오지 못했습니다.';
    }

    get priority() {
        return this.briefing?.priority;
    }

    get caseNumber() {
        return this.briefing?.caseNumber;
    }

    get headerTitle() {
        const asset = this.briefing?.targetAssetName;
        return asset ? `${asset} 출동 브리핑` : '출동 브리핑';
    }

    get slaRemaining() {
        return this.briefing?.slaRemaining || '—';
    }

    // 산정 시각 — 규칙 엔진이 Impact·보증·Priority를 판정한 시각(시:분)
    get calculatedAtText() {
        return this.formatTime(this.briefing?.calculatedAt);
    }

    // ── Priority 승인 상태 (step9) ──
    get isApproved() {
        return this.briefing?.isApproved === true;
    }

    // 승인 전: "Priority · {High} 제안" / 승인 후: "Priority {High} · 담당자 승인"
    get priorityBadgeText() {
        return this.isApproved
            ? `Priority ${this.priority} · 담당자 승인`
            : `Priority · ${this.priority} 제안`;
    }

    get priorityBadgeClass() {
        return this.isApproved
            ? 'slds-badge priority-badge-approved'
            : 'slds-badge priority-badge';
    }

    // 승인 전: "Priority 승인 · 출동 확정" / 승인 후: "출동 확정됨 · {02:45}"
    get approveButtonLabel() {
        return this.isApproved
            ? `출동 확정됨 · ${this.approvedAtText}`
            : 'Priority 승인 · 출동 확정';
    }


    get approvedByText() {
        const name = this.briefing?.approvedByName || '담당자';
        return `${name} · ${this.approvedAtText}`;
    }

    get approvedAtText() {
        return this.formatTime(this.briefing?.approvedAt);
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

    async handleEvidence() {
        const caseId = this.recordId || this._stateRecordId;
        if (!caseId) {
            return;
        }
        // step5 브리핑 → step7 원기록 이동. otBriefingNavigator와 동일하게
        // 워크벤치처럼 UrlAddressable 컴포넌트로 열어 App Page 껍데기 없이 화면만 띄운다.
        const pageReference = {
            type: 'standard__component',
            attributes: { componentName: 'c__otAssetEvidenceHistory' },
            state: { c__recordId: caseId }
        };

        if (this.isConsole) {
            const focused = await getFocusedTabInfo();
            const subtabId = await openSubtab({
                parentTabId: focused.parentTabId || focused.tabId,
                pageReference,
                focus: true
            });
            await focusTab(subtabId);
        } else {
            this[NavigationMixin.Navigate](pageReference);
        }
    }

    // Slack 인계 → 전문가 소집 Flow(채널 생성·전문가 초대·Case 요약 발신)를 모달로 실행.
    handleSlack() {
        if (!this.effectiveRecordId) {
            return;
        }
        this.swarmFlowLoaded = false;
        this.showSwarmFlow = true;
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
        // Flow 첫 화면 렌더 시 로딩 종료로 간주(스피너→카드).
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

    async handleApprove() {
        const caseId = this.effectiveRecordId;
        if (!caseId || this.isApproved) {
            return;
        }
        try {
            await approveDispatch({ caseId });
            await refreshApex(this._wiredBriefing);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: '출동 확정',
                    message: `Priority ${this.priority} 승인 및 출동이 확정됐습니다.`,
                    variant: 'success'
                })
            );
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: '출동 확정 실패',
                    message: e?.body?.message || '승인을 저장하지 못했습니다.',
                    variant: 'error'
                })
            );
        }
    }

    notReady(feature) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: `${feature} — 준비 중`,
                message: '해당 기능은 후속 작업에서 연결됩니다.',
                variant: 'info'
            })
        );
    }

    get rationale() {
        return this.briefing?.priorityRationale;
    }

    get maxDriftText() {
        const r = this.rationale;
        if (!r || r.maxDriftValue == null) {
            return '';
        }
        return `${r.maxDriftValue}% · ${r.comparedCount}대 중 최대`;
    }

    // 프로토타입 5행 산정 인자 테이블 — 각 인자에 기여도 배지 클래스 부여
    get rationaleFactors() {
        const factors = this.rationale?.factors || [];
        return factors.map((f) => ({
            ...f,
            valueText: f.available ? f.value : '—',
            contributionText: f.available ? f.contribution : '준비중',
            contributionClass: f.available
                ? this.contributionBadgeClass(f.contribution)
                : 'slds-badge'
        }));
    }

    contributionBadgeClass(contribution) {
        if (contribution === '높음') {
            return 'slds-badge slds-theme_error';
        }
        if (contribution === '보통') {
            return 'slds-badge slds-theme_warning';
        }
        return 'slds-badge';
    }

    // 12대 비교 행 — 대표값을 표시용으로 가공(A-07 강조 플래그 포함)
    get comparisonRows() {
        const rows = this.briefing?.comparisons || [];
        const targetName = this.briefing?.targetAssetName;
        return rows.map((c) => {
            const isTarget = c.assetName === targetName;
            return {
                ...c,
                key: c.assetId,
                isTarget,
                driftText: c.driftFromBaseline == null ? '—' : `${c.driftFromBaseline}%`,
                measuredText: c.measuredValue == null ? '—' : `${c.measuredValue} L/min`,
                revisionText: c.appliedRevision || '—',
                rowClass: isTarget
                    ? 'slds-hint-parent target-row'
                    : 'slds-hint-parent',
                trendClass: this.trendBadgeClass(c.trendFlag),
                pastFailureText: c.hasPastFailure ? '있음' : '—'
            };
        });
    }

    trendBadgeClass(trend) {
        if (trend === '이상') {
            return 'slds-badge slds-theme_error';
        }
        if (trend === '주의') {
            return 'slds-badge slds-theme_warning';
        }
        return 'slds-badge';
    }

    get hasComparisons() {
        return (this.briefing?.comparisons || []).length > 0;
    }

    get similarCasesSummary() {
        return this.toSections(this.briefing?.similarCasesSummary);
    }

    get briefingBody() {
        return this.toSections(this.briefing?.briefingBody);
    }

    // '■' 섹션 마커 단위로 문단을 나눠 가독성 확보
    toSections(raw) {
        if (!raw) {
            return raw;
        }
        return raw
            .split('■')
            .map((seg) => seg.trim())
            .filter((seg) => seg.length > 0)
            .map((seg) => `<p class="briefing-section">■ ${seg}</p>`)
            .join('');
    }

    get hasPastFailure() {
        return this.rationale?.hasPastFailure === true;
    }
}

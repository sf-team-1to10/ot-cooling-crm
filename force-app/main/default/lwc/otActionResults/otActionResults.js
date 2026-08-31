import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon
} from 'lightning/platformWorkspaceApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getActions from '@salesforce/apex/T5ProblemRcaController.getActions';

export default class OtActionResults extends LightningElement {
    // Record page에서는 자동 주입, App Page에서는 pageReference state에서 해석한다.
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        const stateId = pageRef?.state?.c__recordId || pageRef?.attributes?.recordId;
        if (stateId) {
            this._stateRecordId = stateId;
        }
    }

    actions;
    error;

    @wire(getActions, { caseId: '$effectiveRecordId' })
    wiredActions({ data, error }) {
        if (data) {
            this.actions = data;
            this.error = undefined;
            this.labelEnclosingTab();
        } else if (error) {
            this.error = error;
            this.actions = undefined;
        }
    }

    @wire(EnclosingTabId)
    setTabId(tabId) {
        this._tabId = tabId;
        this.labelEnclosingTab();
    }

    async labelEnclosingTab() {
        if (this._tabLabeled || !this._tabId || !this.actions?.problemNumber) {
            return;
        }
        this._tabLabeled = true;
        await setTabLabel(this._tabId, `${this.actions.problemNumber} 조치 결과`);
        await setTabIcon(this._tabId, 'standard:task');
    }

    get effectiveRecordId() {
        // undefined를 반환해야 wire가 실행되지 않는다(null이면 Apex가 예외).
        return this.recordId || this._stateRecordId || undefined;
    }

    get isLoading() {
        return !this.actions && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || '조치 결과를 불러오지 못했습니다.';
    }

    get correctiveCount() {
        return this.actions?.correctiveCount ?? 0;
    }

    get preventiveCount() {
        return this.actions?.preventiveCount ?? 0;
    }

    get totalCount() {
        return this.actions?.totalCount ?? 0;
    }

    get workOrders() {
        return (this.actions?.workOrders || []).map((wo) => ({
            ...wo,
            badgeClass: wo.isCorrective
                ? 'slds-badge scope-corrective'
                : 'slds-badge scope-preventive',
            badgeLabel: wo.isCorrective ? '시정' : '예방'
        }));
    }

    get hasWorkOrders() {
        return (this.actions?.workOrders || []).length > 0;
    }

    // 점검표 개정 — 시나리오 기반 정적 3행 (org 전용 객체 없음)
    get checklistRows() {
        return [
            { key: 'flow', item: '유량·차압 측정', rev2: '포함', rev3: '포함', isNew: false },
            { key: 'filter', item: '필터 상태 확인', rev2: '포함', rev3: '포함', isNew: false },
            {
                key: 'refit',
                item: '변경·재작업 위치 체결 상태 재확인',
                rev2: '없음',
                rev3: '신규 추가',
                isNew: true
            }
        ];
    }

    // 신규사례 Article 초안 근거값 — 수치는 실데이터, 문구는 정적
    get articleEvidence() {
        return this.actions?.articleEvidence;
    }

    get commissionText() {
        const e = this.articleEvidence;
        return e?.commissionFail != null && e?.commissionPass != null
            ? `${e.commissionFail} → ${e.commissionPass}`
            : '—';
    }

    get recoveryText() {
        const e = this.articleEvidence;
        return e?.recoveryFail != null && e?.recoveryPass != null
            ? `${e.recoveryFail} → ${e.recoveryPass}`
            : '—';
    }

    get evidenceSource() {
        const e = this.articleEvidence;
        const parts = [];
        if (e?.caseNumber) {
            parts.push(`Case ${e.caseNumber}`);
        }
        if (e?.problemNumber) {
            parts.push(e.problemNumber);
        }
        return parts.length ? parts.join(' · ') : '—';
    }

    // 등록 검토·보류는 Knowledge 순환 후속 작업에서 연결한다.
    handleArticleReview() {
        this.notReady('Article 등록 검토');
    }

    handleArticleHold() {
        this.notReady('Article 보류');
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
}

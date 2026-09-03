import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon
} from 'lightning/platformWorkspaceApi';
import getActions from '@salesforce/apex/T5ProblemRcaController.getActions';

export default class OtActionResults extends LightningElement {
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        this._stateRecordId =
            pageRef?.state?.c__recordId || pageRef?.attributes?.recordId || undefined;
    }

    get effectiveRecordId() {
        return this.recordId || this._stateRecordId || undefined;
    }

    @wire(EnclosingTabId)
    setTabId(tabId) {
        this._tabId = tabId;
        this.labelEnclosingTab();
    }

    async labelEnclosingTab() {
        if (!this._tabId) return;
        const short = String(this.problemNumber || '').replace(/^0+/, '').slice(-4);
        const label = short ? `시정·예방 · ${short}` : '시정·예방';
        try {
            await setTabLabel(this._tabId, label);
            await setTabIcon(this._tabId, 'standard:problem');
        } catch (e) { /* 콘솔 외 컨텍스트 무시 */ }
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

    get isLoading() {
        return !this.actions && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || '조치 결과를 불러오지 못했습니다.';
    }

    get problemNumber() {
        return this.actions?.problemNumber || '';
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

    get checklistRows() {
        return [
            { key: 'flow', item: '유량·차압 측정', rev2: '포함', rev3: '포함', isNew: false },
            { key: 'filter', item: '필터 상태 확인', rev2: '포함', rev3: '포함', isNew: false },
            { key: 'refit', item: '변경·재작업 위치 체결 상태 재확인', rev2: '없음', rev3: '신규 추가', isNew: true }
        ];
    }

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
        if (e?.caseNumber) parts.push(`Case ${e.caseNumber}`);
        if (e?.problemNumber) parts.push(e.problemNumber);
        return parts.length ? parts.join(' · ') : '—';
    }

}

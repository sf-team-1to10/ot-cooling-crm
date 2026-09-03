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
        if (this._tabLabeled || !this._tabId || !this.caseNumber) return;
        this._tabLabeled = true;
        try {
            await setTabLabel(this._tabId, `시정·예방 · Case ${this.caseNumber}`);
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

    get caseNumber() {
        return this.actions?.caseNumber || '';
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

    get isApproved() {
        return this.totalCount > 0;
    }

    get approvalStatus() {
        return this.isApproved ? '승인 완료' : '승인 대기';
    }

    get approvalStatusClass() {
        return this.isApproved ? 'chip chip--pos' : 'chip chip--warn';
    }

    get workOrders() {
        return (this.actions?.workOrders || []).map((wo) => ({
            ...wo,
            rowClass: wo.isCorrective ? 'wo-row wo-row--corr' : 'wo-row wo-row--prev',
            badgeClass: wo.isCorrective ? 'chip chip--neg' : 'chip chip--warn',
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
}

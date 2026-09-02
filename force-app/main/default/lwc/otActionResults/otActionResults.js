import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon,
    IsConsoleNavigation
} from 'lightning/platformWorkspaceApi';
import { openOrFocusSubtab } from 'c/otConsoleNav';
import getActions from '@salesforce/apex/T5ProblemRcaController.getActions';

export default class OtActionResults extends NavigationMixin(LightningElement) {
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

    @wire(IsConsoleNavigation) isConsoleNavigation;

    get isConsole() {
        return this.isConsoleNavigation?.data === true;
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
        await setTabLabel(this._tabId, '조치 결과');
        await setTabIcon(this._tabId, 'standard:task');
    }

    actions;
    error;

    @wire(getActions, { caseId: '$effectiveRecordId' })
    wiredActions({ data, error }) {
        if (data) {
            this.actions = data;
            this.error = undefined;
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

    async handleSubtab(event) {
        this.navigate(event.currentTarget.dataset.goto);
    }

    async navigate(target) {
        const rid = this.effectiveRecordId;
        if (!target || !rid) {
            return;
        }

        if (target === 'case') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: rid, objectApiName: 'Case', actionName: 'view' }
            });
            return;
        }

        if (this.isConsole) {
            await openOrFocusSubtab(target, rid);
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__component',
                attributes: { componentName: target },
                state: { c__recordId: rid }
            });
        }
    }
}

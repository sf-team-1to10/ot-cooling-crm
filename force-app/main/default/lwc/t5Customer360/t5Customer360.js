import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon
} from 'lightning/platformWorkspaceApi';
import getCustomer360 from '@salesforce/apex/T5Customer360Controller.getCustomer360';

export default class T5Customer360 extends LightningElement {
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
        const name = (this.accountName || '').slice(0, 8);
        const label = name ? `고객 · ${name}` : '고객 360';
        try {
            await setTabLabel(this._tabId, label);
            await setTabIcon(this._tabId, 'standard:account');
        } catch (e) { /* 콘솔 외 컨텍스트 무시 */ }
    }

    data;
    error;

    @wire(getCustomer360, { caseId: '$effectiveRecordId' })
    wiredData({ data, error }) {
        if (data) {
            this.data = data;
            this.error = undefined;
            this.labelEnclosingTab();
        } else if (error) {
            this.error = error;
            this.data = undefined;
        }
    }

    get isLoading() {
        return !this.data && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || 'Customer 360을 불러오지 못했습니다.';
    }

    get accountName() {
        return this.data?.accountName || '';
    }

    get profile() {
        return this.data?.profile;
    }

    get contactEmail() {
        return this.data?.profile?.contactEmail || '—';
    }

    get contactPhone() {
        return this.data?.profile?.contactPhone || '—';
    }

    get contactAddress() {
        return this.data?.profile?.contactAddress || '—';
    }

    get contactIndustry() {
        return this.data?.profile?.industry || '—';
    }

    get kpiCsat() {
        return '96';
    }

    get kpiResponseSla() {
        return '30분';
    }

    get kpiContractType() {
        const c = this.currentContract;
        return c ? c.name?.replace(/.*?(보증|계약).*/, '$1') || '—' : '—';
    }

    get kpiContractStatus() {
        const c = this.currentContract;
        return c ? (c.isExpired ? '만료' : '계약 유효') : '—';
    }

    get kpiContractStatusClass() {
        const c = this.currentContract;
        const ok = c && !c.isExpired;
        return ok ? 'c360-kpi-v c360-kpi-good c360-kpi-sm' : 'c360-kpi-v c360-kpi-sm';
    }

    get kpiContractExpiry() {
        const c = this.currentContract;
        if (!c?.endDate) return '—';
        return '계약 만료 ' + c.endDate;
    }

    get currentContract() {
        const contracts = this.data?.contracts || [];
        return contracts.find(c => c.isCurrent) || contracts[0] || null;
    }

    get hasContracts() {
        return this.data?.contracts?.length > 0;
    }

    get contracts() {
        return (this.data?.contracts || []).map((c) => ({
            ...c,
            badgeLabel: c.isExpired ? '만료' : c.isCurrent ? '계약 유효' : c.status,
            badgeClass: c.isExpired
                ? 'slds-badge c360-badge-warn'
                : c.isCurrent
                    ? 'slds-badge c360-badge-ok'
                    : 'slds-badge c360-badge-neutral',
            endDateFormatted: c.endDate || '—'
        }));
    }

    get hasAssets() {
        return this.data?.assets?.length > 0;
    }

    get assets() {
        return this.data?.assets || [];
    }

    get hasPastCases() {
        return this.data?.pastCases?.length > 0;
    }

    get pastCases() {
        return this.data?.pastCases || [];
    }

    get hasOpportunities() {
        return this.data?.opportunities?.length > 0;
    }

    get opportunities() {
        return (this.data?.opportunities || []).map((o) => ({
            ...o,
            badgeLabel: o.stageName || '',
            badgeClass: o.isWon
                ? 'slds-badge c360-badge-ok'
                : o.isClosed
                    ? 'slds-badge c360-badge-warn'
                    : 'slds-badge c360-badge-neutral',
            amountFormatted: o.amount != null ? new Intl.NumberFormat('ko-KR', { style: 'currency', currency: 'KRW' }).format(o.amount) : '—',
            closeDateFormatted: o.closeDate || '—'
        }));
    }

    activeTab = 'contract';

    get isContract() { return this.activeTab === 'contract'; }
    get isProduct() { return this.activeTab === 'product'; }
    get isProblem() { return this.activeTab === 'problem'; }
    get isSales() { return this.activeTab === 'sales'; }

    get contractTabClass() { return this.tabClass('contract'); }
    get productTabClass() { return this.tabClass('product'); }
    get problemTabClass() { return this.tabClass('problem'); }
    get salesTabClass() { return this.tabClass('sales'); }

    tabClass(key) {
        return this.activeTab === key ? 'c360-tabbtn on' : 'c360-tabbtn';
    }

    handleC360Tab(event) {
        this.activeTab = event.currentTarget.dataset.c360;
    }

}

import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon,
    IsConsoleNavigation
} from 'lightning/platformWorkspaceApi';
import { openOrFocusSubtab } from 'c/otConsoleNav';
import getCustomer360 from '@salesforce/apex/T5Customer360Controller.getCustomer360';

export default class T5Customer360 extends NavigationMixin(LightningElement) {
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
        if (this._tabLabeled || !this._tabId) {
            return;
        }
        this._tabLabeled = true;
        await setTabLabel(this._tabId, 'Customer 360');
        await setTabIcon(this._tabId, 'standard:contact');
    }

    data;
    error;

    @wire(getCustomer360, { caseId: '$effectiveRecordId' })
    wiredData({ data, error }) {
        if (data) {
            this.data = data;
            this.error = undefined;
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
            itemClass: c.isCurrent ? 'slds-item section-row row-current' : 'slds-item section-row'
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
                    : 'slds-badge c360-badge-neutral'
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

    @wire(IsConsoleNavigation) isConsoleNavigation;

    get isConsole() {
        return this.isConsoleNavigation?.data === true;
    }

    async handleSubtab(event) {
        const target = event.currentTarget.dataset.goto;
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

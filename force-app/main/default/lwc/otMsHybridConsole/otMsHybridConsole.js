import { LightningElement, api, wire } from 'lwc';
import { IsConsoleNavigation } from 'lightning/platformWorkspaceApi';
import { openOrFocusSubtab } from 'c/otConsoleNav';
import { NavigationMixin } from 'lightning/navigation';
import getCaseId from '@salesforce/apex/OTMsSessionResolver.getCaseId';

export default class OtMsHybridConsole extends NavigationMixin(LightningElement) {
    @api recordId;

    caseId;
    resolveError;

    @wire(getCaseId, { recordId: '$recordId' })
    wiredCaseId({ data, error }) {
        if (data) {
            this.caseId = data;
            this.resolveError = undefined;
        } else if (error) {
            this.resolveError = error;
            this.caseId = undefined;
        }
    }

    get isResolved() {
        return !!this.caseId;
    }

    get isResolving() {
        return !this.caseId && !this.resolveError;
    }

    get resolveErrorMessage() {
        return this.resolveError?.body?.message || 'MessagingSession에서 Case를 찾을 수 없습니다.';
    }

    activeTab = 'case';

    get isCaseTab() { return this.activeTab === 'case'; }
    get isCustomer360Tab() { return this.activeTab === 'customer360'; }
    get isBriefingTab() { return this.activeTab === 'briefing'; }
    get isCandidatesTab() { return this.activeTab === 'candidates'; }

    tabClass(key) {
        return this.activeTab === key ? 'ms-tab on' : 'ms-tab';
    }

    get caseTabClass() { return this.tabClass('case'); }
    get customer360TabClass() { return this.tabClass('customer360'); }
    get briefingTabClass() { return this.tabClass('briefing'); }
    get candidatesTabClass() { return this.tabClass('candidates'); }

    handleTabSwitch(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    @wire(IsConsoleNavigation) isConsoleNavigation;

    get isConsole() {
        return this.isConsoleNavigation?.data === true;
    }

    async handleSubtab(event) {
        const target = event.currentTarget.dataset.goto;
        if (!target || !this.caseId) return;
        if (this.isConsole) {
            await openOrFocusSubtab(target, this.caseId);
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__component',
                attributes: { componentName: target },
                state: { c__recordId: this.caseId }
            });
        }
    }
}

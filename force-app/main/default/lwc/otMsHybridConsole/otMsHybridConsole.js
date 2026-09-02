import { LightningElement, api, wire } from 'lwc';
import getCaseId from '@salesforce/apex/OTMsSessionResolver.getCaseId';

export default class OtMsHybridConsole extends LightningElement {
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

}

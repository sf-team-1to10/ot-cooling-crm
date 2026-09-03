import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    focusTab
} from 'lightning/platformWorkspaceApi';
import getSessionInfo from '@salesforce/apex/OtMsInfoPanelController.getSessionInfo';

export default class OtMsCaseDetail extends NavigationMixin(LightningElement) {
    @api recordId;

    info;
    error;

    @wire(IsConsoleNavigation) isConsole;

    @wire(getSessionInfo, { sessionId: '$recordId' })
    wired({ data, error }) {
        if (data)  { this.info = data;  this.error = undefined; }
        if (error) { this.error = error; this.info = undefined; }
    }

    get isLoading()    { return !this.info && !this.error; }
    get hasError()     { return !!this.error; }
    get errorMessage() { return this.error?.body?.message || 'Case 정보를 불러오지 못했습니다.'; }

    get hasCaseId()      { return !!this.info?.caseId; }
    get caseUrl()        { return this.info?.caseId ? '/' + this.info.caseId : '#'; }
    get accountDisplay() { return this.info?.accountName || '—'; }
    get assetDisplay()   { return this.info?.assetName   || '—'; }
    get caseTypeDisplay()   { return this.info?.caseType   || '—'; }
    get caseReasonDisplay() { return this.info?.caseReason || '—'; }
    get hasSla()         { return !!(this.info?.responseSla || this.info?.recoverySla); }

    get priorityClass() {
        const p = this.info?.casePriority;
        if (p === 'High' || p === 'Critical') return 'ms-badge ms-badge--high';
        if (p === 'Medium') return 'ms-badge ms-badge--medium';
        return 'ms-badge';
    }

    handleCaseClick(event) {
        event.preventDefault();
        if (!this.info?.caseId) return;
        this._openCaseSubtab(this.info.caseId);
    }

    async _openCaseSubtab(caseId) {
        if (!this.isConsole?.data) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: caseId, objectApiName: 'Case', actionName: 'view' }
            });
            return;
        }
        try {
            const focused     = await getFocusedTabInfo();
            const parentTabId = focused.parentTabId || focused.tabId;
            const subtabId    = await openSubtab({
                parentTabId,
                pageReference: {
                    type: 'standard__recordPage',
                    attributes: { recordId: caseId, objectApiName: 'Case', actionName: 'view' }
                },
                focus: true
            });
            await focusTab(subtabId);
        } catch (_) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: caseId, objectApiName: 'Case', actionName: 'view' }
            });
        }
    }

    handleNewCase() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Case', actionName: 'new' }
        });
    }
}

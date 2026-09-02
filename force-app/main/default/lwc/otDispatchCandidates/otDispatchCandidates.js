import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon
} from 'lightning/platformWorkspaceApi';
import getHeader from '@salesforce/apex/T5DispatchCandidatesController.getHeader';

export default class OtDispatchCandidates extends LightningElement {
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    isAssigned = false;

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
        await setTabLabel(this._tabId, '담당자 확정');
        await setTabIcon(this._tabId, 'standard:service_resource');
    }

    header;
    error;

    @wire(getHeader, { caseId: '$effectiveRecordId' })
    wiredHeader({ data, error }) {
        if (data) {
            this.header = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.header = undefined;
        }
    }

    get isLoading() {
        return !this.header && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || '담당자 확정 데이터를 불러오지 못했습니다.';
    }

    get caseNumber() {
        return this.header?.caseNumber || '';
    }

    get appointmentNumber() {
        return this.header?.appointmentNumber || '';
    }

    get eyebrowText() {
        const parts = ['담당자 확정'];
        if (this.caseNumber) parts.push(`Case ${this.caseNumber}`);
        if (this.appointmentNumber) parts.push(this.appointmentNumber);
        return parts.join(' · ');
    }

    get siteLocation() {
        const acct = this.header?.accountName || '';
        const loc = this.header?.siteLocation || '';
        return [acct, loc].filter(Boolean).join(' ');
    }

    get cand1Class() {
        return this.isAssigned ? 'cand-item picked' : 'cand-item top';
    }

    handleAssign() {
        this.isAssigned = true;
    }

}

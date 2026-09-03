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
    selectedCand = 'kang';

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
        const short = (this.caseNumber || '').replace(/^0+/, '').slice(-4);
        const label = short ? `배정 · ${short}` : '배정';
        try {
            await setTabLabel(this._tabId, label);
            await setTabIcon(this._tabId, 'standard:work_order');
        } catch (e) { /* 콘솔 외 컨텍스트 무시 */ }
    }

    header;
    error;

    @wire(getHeader, { caseId: '$effectiveRecordId' })
    wiredHeader({ data, error }) {
        if (data) {
            this.header = data;
            this.error = undefined;
            this.labelEnclosingTab();
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

    get selectedName() {
        const map = { kang: '강시공', lim: '임수리', jeon: '전배관' };
        return map[this.selectedCand] || '';
    }

    candClass(key, extra) {
        if (this.isAssigned) {
            return this.selectedCand === key ? 'cand-item picked' : 'cand-item out';
        }
        const base = this.selectedCand === key ? 'cand-item selected' : 'cand-item';
        return extra ? `${base} ${extra}` : base;
    }

    get cand1Class() { return this.candClass('kang', ''); }
    get cand2Class() { return this.candClass('lim', ''); }
    get cand3Class() { return this.candClass('jeon', ''); }

    handleSelectCand(event) {
        if (this.isAssigned) return;
        this.selectedCand = event.currentTarget.dataset.cand;
    }

    get assignButtonLabel() {
        return `${this.selectedName} 확정`;
    }

    handleAssign() {
        this.isAssigned = true;
    }

}

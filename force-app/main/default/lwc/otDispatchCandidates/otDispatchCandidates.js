import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon
} from 'lightning/platformWorkspaceApi';
import getHeader from '@salesforce/apex/T5DispatchCandidatesController.getHeader';
import confirmAssignment from '@salesforce/apex/T5DispatchAssignController.confirmAssignment';

const CAND_LABEL = { kang: '강시공', lim: '임수리', jeon: '전배관' };
const CAND_CMDT_KEY = { kang: 'Kang_Sikong', lim: null, jeon: null };

export default class OtDispatchCandidates extends LightningElement {
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    isAssigned = false;
    isBusy = false;
    selectedCand = 'kang';
    showSwarmFlow = false;
    swarmFlowInputs = [];

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
        return CAND_LABEL[this.selectedCand] || '';
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

    async handleAssign() {
        const rid = this.effectiveRecordId;
        if (!rid || this.isBusy) return;

        const cmdtKey = CAND_CMDT_KEY[this.selectedCand];
        if (!cmdtKey) {
            this.dispatchEvent(new ShowToastEvent({
                title: `${this.selectedName} — 데모용 후보`,
                message: '실제 데모에서는 강시공만 배정됩니다.',
                variant: 'info'
            }));
            return;
        }

        this.isBusy = true;
        try {
            const r = await confirmAssignment({ caseId: rid, candidateKey: cmdtKey });
            this.isAssigned = true;
            getRecordNotifyChange([{ recordId: rid }]);
            this.swarmFlowInputs = [
                { name: 'recordId', type: 'String', value: r?.resolvedCaseId || rid },
                { name: 'swarmName', type: 'String', value: r?.caseNumber || '' },
                { name: 'swarmDescription', type: 'String', value: r?.caseSubject || '' }
            ];
            this.showSwarmFlow = true;
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: '배정 실패',
                message: e?.body?.message || '알 수 없는 오류',
                variant: 'error'
            }));
        } finally {
            this.isBusy = false;
        }
    }

    handleSwarmFlowStatusChange(event) {
        const status = event.detail.status;
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            this.showSwarmFlow = false;
            this.dispatchEvent(new ShowToastEvent({
                title: `${this.selectedName} 배정 확정`,
                message: 'Swarm 채널을 생성하고 담당자를 초대했습니다.',
                variant: 'success'
            }));
        } else if (status === 'ERROR') {
            this.showSwarmFlow = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Slack 채널 생성 실패',
                message: '배정은 완료됐지만 채널 생성에 실패했습니다. 관리자에게 문의하세요.',
                variant: 'warning'
            }));
        }
    }
}

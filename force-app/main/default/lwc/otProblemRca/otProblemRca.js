import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon
} from 'lightning/platformWorkspaceApi';
import getRca from '@salesforce/apex/T5ProblemRcaController.getRca';

export default class OtProblemRca extends LightningElement {
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
        await setTabLabel(this._tabId, 'RCA');
        await setTabIcon(this._tabId, 'standard:problem');
    }

    rca;
    error;

    @wire(getRca, { caseId: '$effectiveRecordId' })
    wiredRca({ data, error }) {
        if (data) {
            this.rca = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.rca = undefined;
        }
    }

    get isLoading() {
        return !this.rca && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || 'RCA 데이터를 불러오지 못했습니다.';
    }

    get problemNumber() {
        return this.rca?.problemNumber || '';
    }

    get caseNumber() {
        return this.rca?.caseNumber || '';
    }

    get rcaSubject() {
        return this.rca?.subject || '';
    }

    get directCause() {
        return this.rca?.directCause || '—';
    }

    get rootCause() {
        return this.rca?.rootCause || '—';
    }

    get correctiveCount() {
        return this.rca?.correctiveCount ?? 0;
    }

    get preventiveCount() {
        return this.rca?.preventiveCount ?? 0;
    }

    get evidenceFailValue() {
        return this.rca?.evidence?.recoveryFail ?? '—';
    }

    get evidencePassValue() {
        return this.rca?.evidence?.recoveryPass ?? '—';
    }

    get evidenceFlowBefore() {
        return '1,961';
    }

    get evidenceFlowAfter() {
        return '2,080';
    }

    get evidenceSummary() {
        const fail = this.rca?.evidence?.recoveryFail;
        const pass = this.rca?.evidence?.recoveryPass;
        if (fail != null && pass != null) {
            return 'F-07 · ' + fail + ' → ' + pass;
        }
        return '—';
    }

    handleSaveRca() {
    }
}

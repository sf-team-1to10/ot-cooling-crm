import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon
} from 'lightning/platformWorkspaceApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRca from '@salesforce/apex/T5ProblemRcaController.getRca';

export default class OtProblemRca extends LightningElement {
    // Record page에서는 자동 주입, App Page에서는 pageReference state에서 해석한다.
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        const stateId = pageRef?.state?.c__recordId || pageRef?.attributes?.recordId;
        if (stateId) {
            this._stateRecordId = stateId;
        }
    }

    rca;
    error;

    @wire(getRca, { caseId: '$effectiveRecordId' })
    wiredRca({ data, error }) {
        if (data) {
            this.rca = data;
            this.error = undefined;
            this.labelEnclosingTab();
        } else if (error) {
            this.error = error;
            this.rca = undefined;
        }
    }

    @wire(EnclosingTabId)
    setTabId(tabId) {
        this._tabId = tabId;
        this.labelEnclosingTab();
    }

    async labelEnclosingTab() {
        if (this._tabLabeled || !this._tabId || !this.problemNumber) {
            return;
        }
        this._tabLabeled = true;
        await setTabLabel(this._tabId, `${this.problemNumber} RCA`);
        await setTabIcon(this._tabId, 'standard:problem');
    }

    get effectiveRecordId() {
        // undefined를 반환해야 wire가 실행되지 않는다(null이면 Apex가 예외).
        return this.recordId || this._stateRecordId || undefined;
    }

    get isLoading() {
        return !this.rca && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || 'RCA 데이터를 불러오지 못했습니다.';
    }

    get problemNumber() {
        return this.rca?.problemNumber;
    }

    get caseNumberText() {
        return this.rca?.caseNumber || '—';
    }

    get subject() {
        return this.rca?.subject || '—';
    }

    get directCause() {
        return this.rca?.directCause || '—';
    }

    get rootCause() {
        return this.rca?.rootCause || '—';
    }

    get correctiveText() {
        return `시정조치 ${this.rca?.correctiveCount ?? 0}건`;
    }

    get preventiveText() {
        return `예방확인 ${this.rca?.preventiveCount ?? 0}건`;
    }

    // step19(v-actions 조치 생성 결과)는 이번 범위 밖 — 후속 작업에서 연결한다.
    handleApproveScope() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: '영향 범위 승인 — 준비 중',
                message: '조치 생성(시정·예방 Work Order) 화면은 후속 작업에서 연결됩니다.',
                variant: 'info'
            })
        );
    }
}

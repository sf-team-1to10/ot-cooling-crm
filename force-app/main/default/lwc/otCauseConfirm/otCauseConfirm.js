import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon
} from 'lightning/platformWorkspaceApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEvidence from '@salesforce/apex/T5AssetEvidenceController.getEvidence';
import createProblemWithRca from '@salesforce/apex/T5AssetEvidenceController.createProblemWithRca';

export default class OtCauseConfirm extends NavigationMixin(LightningElement) {
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    problemCreated = false;
    createdProblemId;
    creating = false;

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
        const short = String(this.caseNumber || '').replace(/^0+/, '').slice(-4);
        const label = short ? `원인 확인 · ${short}` : '원인 확인';
        try {
            await setTabLabel(this._tabId, label);
            await setTabIcon(this._tabId, 'standard:work_order');
        } catch (e) { /* 콘솔 외 컨텍스트 무시 */ }
    }

    evidence;
    error;

    @wire(getEvidence, { caseId: '$effectiveRecordId' })
    wiredEvidence({ data, error }) {
        if (data) {
            this.evidence = data;
            this.error = undefined;
            this.labelEnclosingTab();
        } else if (error) {
            this.error = error;
            this.evidence = undefined;
        }
    }

    get isLoading() {
        return !this.evidence && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || '원인확정 데이터를 불러오지 못했습니다.';
    }

    get caseNumber() {
        return this.evidence?.caseNumber || '';
    }

    get assetName() {
        return this.evidence?.assetName || '';
    }

    get revisionText() {
        return this.evidence?.summary?.revisionText || '';
    }

    get firstFailValue() {
        return this.evidence?.summary?.firstFailValue || '—';
    }

    get retestPassValue() {
        return this.evidence?.summary?.retestPassValue || '—';
    }

    get timeline() {
        return this.evidence?.timeline || [];
    }

    get hasTimeline() {
        return this.timeline.length > 0;
    }

    async handleCreateProblem() {
        if (this.creating || this.problemCreated) return;
        this.creating = true;
        try {
            const problemId = await createProblemWithRca({ recordId: this.effectiveRecordId });
            this.createdProblemId = problemId;
            this.problemCreated = true;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Problem 생성 완료',
                message: 'Problem이 생성되고 RCA 초안이 기록됐습니다.',
                variant: 'success'
            }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Problem 생성 실패',
                message: e?.body?.message || '생성에 실패했습니다.',
                variant: 'error'
            }));
        } finally {
            this.creating = false;
        }
    }

    handleGoRca() {
        if (this.createdProblemId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.createdProblemId,
                    objectApiName: 'Problem',
                    actionName: 'view'
                }
            });
        }
    }
}

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
        if (this._tabLabeled || !this._tabId) return;
        this._tabLabeled = true;
        try {
            await setTabLabel(this._tabId, '자산 이력');
            await setTabIcon(this._tabId, 'standard:asset_relationship');
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
        return this.error?.body?.message || '자산 이력 데이터를 불러오지 못했습니다.';
    }

    get revisionText() {
        return this.evidence?.summary?.revisionText || '—';
    }

    get firstFailValue() {
        return this.evidence?.summary?.firstFailValue || '—';
    }

    get retestPassValue() {
        return this.evidence?.summary?.retestPassValue || '—';
    }

    get timeline() {
        return (this.evidence?.timeline || []).map((n) => ({
            ...n,
            nodeClass: n.state === 'hit'
                ? 'tl-node tl-node--hit'
                : n.state === 'ok'
                    ? 'tl-node tl-node--ok'
                    : 'tl-node'
        }));
    }

    get hasTimeline() {
        return (this.evidence?.timeline || []).length > 0;
    }

    // ─── 오늘의 측정 요약 (2026 장애복구 WO) ───
    get recovery() {
        return this.evidence?.recovery;
    }

    get hasRecovery() {
        return this.recovery?.hasData === true;
    }

    get torqueBefore() {
        const v = this.recovery?.torqueBefore;
        return v ? `${v} N·m` : '—';
    }

    get torqueAfter() {
        const v = this.recovery?.torqueAfter;
        return v ? `${v} N·m` : '—';
    }

    get flowAfter() {
        const v = this.recovery?.flowAfter;
        return v ? `${v} L/min` : '—';
    }

    get recoveryEyebrow() {
        const wo = this.recovery?.woNumber ? `WO ${this.recovery.woNumber}` : '';
        const dt = this.recovery?.recoveryDateText || '';
        return [wo, dt].filter(Boolean).join(' · ');
    }

    get relatedCaseNumber() {
        return this.recovery?.caseNumber || '—';
    }

    get measurementPoint() {
        return this.recovery?.measurementPoint || '—';
    }

    get completedAtText() {
        return this.recovery?.completedAtText || '—';
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

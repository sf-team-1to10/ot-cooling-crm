import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon,
    IsConsoleNavigation
} from 'lightning/platformWorkspaceApi';
import { openOrFocusSubtab } from 'c/otConsoleNav';
import getEvidence from '@salesforce/apex/T5AssetEvidenceController.getEvidence';

export default class OtCauseConfirm extends NavigationMixin(LightningElement) {
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    problemCreated = false;

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        this._stateRecordId =
            pageRef?.state?.c__recordId || pageRef?.attributes?.recordId || undefined;
    }

    get effectiveRecordId() {
        return this.recordId || this._stateRecordId || undefined;
    }

    @wire(IsConsoleNavigation) isConsoleNavigation;

    get isConsole() {
        return this.isConsoleNavigation?.data === true;
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
        await setTabLabel(this._tabId, '원인확정');
        await setTabIcon(this._tabId, 'standard:incident');
    }

    evidence;
    error;

    @wire(getEvidence, { caseId: '$effectiveRecordId' })
    wiredEvidence({ data, error }) {
        if (data) {
            this.evidence = data;
            this.error = undefined;
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

    handleCreateProblem() {
        this.problemCreated = true;
    }

    handleGoRca() {
        this.navigate('c__otProblemRca');
    }

    async handleSubtab(event) {
        this.navigate(event.currentTarget.dataset.goto);
    }

    async navigate(target) {
        const rid = this.effectiveRecordId;
        if (!target || !rid) {
            return;
        }

        if (target === 'case') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: rid, objectApiName: 'Case', actionName: 'view' }
            });
            return;
        }

        if (this.isConsole) {
            await openOrFocusSubtab(target, rid);
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__component',
                attributes: { componentName: target },
                state: { c__recordId: rid }
            });
        }
    }
}

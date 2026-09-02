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

export default class OtAssetEvidenceHistory extends NavigationMixin(LightningElement) {
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

    @wire(IsConsoleNavigation) isConsoleNavigation;

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

    // EnclosingTabId wire는 탭 컨텍스트가 준비된 후에 tabId를 반응형으로 준다.
    @wire(EnclosingTabId)
    setTabId(tabId) {
        this._tabId = tabId;
        this.labelEnclosingTab();
    }

    async labelEnclosingTab() {
        if (this._tabLabeled || !this._tabId || !this.caseNumber) {
            return;
        }
        this._tabLabeled = true;
        await setTabLabel(this._tabId, `${this.caseNumber} 이력 근거`);
        // standard: 계열 아이콘은 콘솔 탭에서 다른 탭과 동일한 크기로 렌더된다.
        await setTabIcon(this._tabId, 'standard:timesheet_entry');
    }

    get effectiveRecordId() {
        // undefined를 반환해야 wire가 실행되지 않는다(null이면 Apex가 예외).
        return this.recordId || this._stateRecordId || undefined;
    }

    get isConsole() {
        return this.isConsoleNavigation?.data === true;
    }

    get isLoading() {
        return !this.evidence && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || '원기록 데이터를 불러오지 못했습니다.';
    }

    get caseNumber() {
        return this.evidence?.caseNumber;
    }

    get caseNumberText() {
        return this.caseNumber || '—';
    }

    get summary() {
        return this.evidence?.summary;
    }

    get revisionText() {
        return this.summary?.revisionText || '—';
    }

    get firstFailValue() {
        return this.summary?.firstFailValue || '—';
    }

    get retestPassValue() {
        return this.summary?.retestPassValue || '—';
    }

    get recordCount() {
        return (this.evidence?.timeline || []).length;
    }

    get hasTimeline() {
        return (this.evidence?.timeline || []).length > 0;
    }

    get timeline() {
        return (this.evidence?.timeline || []).map((node) => ({
            ...node,
            nodeClass: node.state ? `tl-node ${node.state}` : 'tl-node',
            hasSrc: !!node.source
        }));
    }

    async handleBackToBriefing() {
        if (!this.effectiveRecordId) {
            return;
        }
        const target = 'c__otDispatchBriefingWorkbench';

        if (this.isConsole) {
            await openOrFocusSubtab(target, this.effectiveRecordId);
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__component',
                attributes: { componentName: target },
                state: { c__recordId: this.effectiveRecordId }
            });
        }
    }
}
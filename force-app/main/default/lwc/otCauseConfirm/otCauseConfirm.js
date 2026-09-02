import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon,
    IsConsoleNavigation
} from 'lightning/platformWorkspaceApi';
import { openOrFocusSubtab } from 'c/otConsoleNav';

// 프로토타입 v-cause(19) — 현장 근거로 확정된 원인을 Case의 Problem으로 승격.
export default class OtCauseConfirm extends NavigationMixin(LightningElement) {
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    // "Problem 생성·RCA 기록" 클릭 시 같은 화면에서 생성 상태로 전환(프로토타입 applyCause).
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

    handleCreateProblem() {
        this.problemCreated = true;
    }

    // "RCA 검토 →" — 20번(otProblemRca) 탭으로 진행.
    handleGoRca() {
        this.navigate('c__otProblemRca');
    }

    async handleSubtab(event) {
        const target = event.currentTarget.dataset.goto;
        this.navigate(target);
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
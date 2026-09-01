import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon,
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    focusTab
} from 'lightning/platformWorkspaceApi';

// 프로토타입 v-cause(19) → v-rca(20) → v-actions(21)를 한 화면의 내부 3단계로 담는다.
// 원인 확정 → Problem 생성 → RCA·범위 확정 → 조치 자동 파급, 하나의 Problem/RCA 라이프사이클.
export default class OtRcaWorkbench extends NavigationMixin(LightningElement) {
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    // 'cause' → 'rca' → 'actions'
    step = 'cause';

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

    // standard__component 서브탭은 로드 완료 시 라벨을 'Loading...'으로 덮으므로,
    // EnclosingTabId wire(=로드 후)로 tabId를 받아 라벨/아이콘을 다시 설정한다.
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
        await setTabLabel(this._tabId, 'RCA·예방');
        await setTabIcon(this._tabId, 'standard:problem');
    }

    get isCause() {
        return this.step === 'cause';
    }
    get isRca() {
        return this.step === 'rca';
    }
    get isActions() {
        return this.step === 'actions';
    }

    // 19번 "Problem 생성 · RCA 기록" — 현장 근거로 확정된 원인을 Case의 Problem으로 승격.
    handleCreateProblem() {
        this.step = 'rca';
    }

    // 20번 "RCA·범위 확정 저장" — 저장이 PRI_ Flow(시정·예방 WO)와 Knowledge 초안을 자동 실행.
    handleSaveRca() {
        this.step = 'actions';
    }

    // 서브탭 클릭 → 다른 장면으로 이동.
    async handleSubtab(event) {
        const target = event.currentTarget.dataset.goto;
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

        const pageReference = {
            type: 'standard__component',
            attributes: { componentName: target },
            state: { c__recordId: rid }
        };

        if (this.isConsole) {
            const focused = await getFocusedTabInfo();
            const subtabId = await openSubtab({
                parentTabId: focused.parentTabId || focused.tabId,
                pageReference,
                focus: true
            });
            await focusTab(subtabId);
        } else {
            this[NavigationMixin.Navigate](pageReference);
        }
    }
}

import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon,
    IsConsoleNavigation
} from 'lightning/platformWorkspaceApi';
import { openOrFocusSubtab } from 'c/otConsoleNav';

export default class OtDispatchCandidates extends NavigationMixin(LightningElement) {
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    isAssigned = false;

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
        await setTabLabel(this._tabId, '담당자 확정');
        await setTabIcon(this._tabId, 'standard:service_resource');
    }

    // 1순위 후보 카드 — 확정 시 picked 상태로 전환
    get cand1Class() {
        return this.isAssigned ? 'cand-item picked' : 'cand-item top';
    }

    // 강시공 확정 — 프로토타입 applyAssign(배지·버튼·배정 필드 전환). 시스템이 아니라 사람이 선택.
    handleAssign() {
        this.isAssigned = true;
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

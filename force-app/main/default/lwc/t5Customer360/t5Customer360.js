import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon,
    IsConsoleNavigation
} from 'lightning/platformWorkspaceApi';
import { openOrFocusSubtab } from 'c/otConsoleNav';

export default class T5Customer360 extends NavigationMixin(LightningElement) {
    @api recordId; // Record page에 직접 놓일 때 플랫폼 주입
    _stateRecordId; // 서브탭(UrlAddressable)로 열릴 때 URL state에서 해석
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

    // standard__component 서브탭은 로드 완료 시 라벨을 'Loading...'으로 덮으므로,
    // 이 wire(=로드 후)로 tabId를 받아 라벨/아이콘을 다시 설정해 최종 고정한다.
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
        await setTabLabel(this._tabId, 'Customer 360');
        // standard: 계열 아이콘이 다른 콘솔 탭과 크기가 맞는다.
        await setTabIcon(this._tabId, 'standard:contact');
    }

    // 하단 탭 전환 상태 (프로토타입 c360-tabbtn)
    activeTab = 'contract';

    get isContract() {
        return this.activeTab === 'contract';
    }
    get isProduct() {
        return this.activeTab === 'product';
    }
    get isProblem() {
        return this.activeTab === 'problem';
    }
    get isSales() {
        return this.activeTab === 'sales';
    }

    get contractTabClass() {
        return this.tabClass('contract');
    }
    get productTabClass() {
        return this.tabClass('product');
    }
    get problemTabClass() {
        return this.tabClass('problem');
    }
    get salesTabClass() {
        return this.tabClass('sales');
    }

    tabClass(key) {
        return this.activeTab === key ? 'c360-tabbtn on' : 'c360-tabbtn';
    }

    handleC360Tab(event) {
        this.activeTab = event.currentTarget.dataset.c360;
    }

    @wire(IsConsoleNavigation) isConsoleNavigation;

    get isConsole() {
        return this.isConsoleNavigation?.data === true;
    }

    // 서브탭 클릭 → 다른 장면으로 이동.
    // Case는 레코드 페이지로, 나머지는 UrlAddressable 컴포넌트를 콘솔 서브탭(전체폭)으로 연다.
    async handleSubtab(event) {
        const target = event.currentTarget.dataset.goto;
        const rid = this.effectiveRecordId;
        if (!target || !rid) {
            return;
        }

        if (target === 'case') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: rid,
                    objectApiName: 'Case',
                    actionName: 'view'
                }
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

import { LightningElement, wire } from 'lwc';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon
} from 'lightning/platformWorkspaceApi';

export default class OtServiceContractReview extends LightningElement {
    opportunityCreated = false;
    _tabId;
    _tabLabeled = false;

    @wire(EnclosingTabId)
    setTabId(tabId) {
        this._tabId = tabId;
        this.labelTab();
    }

    async labelTab() {
        if (this._tabLabeled || !this._tabId) {
            return;
        }
        this._tabLabeled = true;
        try {
            await setTabLabel(this._tabId, '성과 리뷰');
            await setTabIcon(this._tabId, 'standard:contract');
        } catch (e) { /* 콘솔 외 컨텍스트 무시 */ }
    }

    handleCreateOpportunity() {
        this.opportunityCreated = true;
    }

}

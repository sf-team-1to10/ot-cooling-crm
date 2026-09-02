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
        await setTabLabel(this._tabId, 'SC-2022-0114');
        await setTabIcon(this._tabId, 'standard:contract');
    }

    handleCreateOpportunity() {
        this.opportunityCreated = true;
    }
}

import { LightningElement } from 'lwc';

export default class OtAssetPortal extends LightningElement {
    selectedAssetId;
    selectedAssetName;
    showReport = false;

    get showList() {
        return !this.showReport;
    }

    get activePage() {
        return this.showReport ? 'intake' : 'assets';
    }

    handleContact(event) {
        this.selectedAssetId = event.detail.assetId;
        this.selectedAssetName = event.detail.assetName;
        this.showReport = true;
    }

    handleBack() {
        this.showReport = false;
        this.selectedAssetId = undefined;
        this.selectedAssetName = undefined;
    }

    // Header nav: '내 자산' returns to the list; '장애 신고' opens the report
    // screen, where step ① lets the user pick an asset when none is selected.
    handleNavigate(event) {
        if (event.detail === 'assets') {
            this.handleBack();
        } else if (event.detail === 'intake') {
            this.showReport = true;
        }
    }
}

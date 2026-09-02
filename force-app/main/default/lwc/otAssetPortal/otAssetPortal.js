import { LightningElement } from 'lwc';

export default class OtAssetPortal extends LightningElement {
    selectedAssetId;
    selectedAssetName;
    page = 'overview'; // 'overview' | 'assets' | 'detail' | 'intake'
    attentionCount = 0;

    get activePage() {
        if (this.page === 'detail') return 'assets';
        if (this.page === 'intake') return 'intake';
        return this.page;
    }

    get showOverview() { return this.page === 'overview'; }
    get showList()     { return this.page === 'assets'; }
    get showDetail()   { return this.page === 'detail'; }
    get showIntake()   { return this.page === 'intake'; }

    handleNavigate(event) {
        const dest = event.detail;
        if (dest === 'assets') {
            this.page = 'assets';
            this.selectedAssetId = undefined;
            this.selectedAssetName = undefined;
        } else if (dest === 'intake') {
            this.page = 'intake';
        } else if (dest === 'overview') {
            this.page = 'overview';
        }
    }

    handleGoAssets() {
        this.page = 'assets';
    }

    handleContact(event) {
        this.selectedAssetId = event.detail.assetId;
        this.selectedAssetName = event.detail.assetName;
        this.page = 'detail';
    }

    handleAttentionCount(event) {
        this.attentionCount = event.detail;
    }

    handleOpenReport() {
        this.page = 'intake';
    }

    handleBackToList() {
        this.page = 'assets';
        this.selectedAssetId = undefined;
        this.selectedAssetName = undefined;
    }

    handleBackFromReport() {
        this.page = this.selectedAssetId ? 'detail' : 'assets';
    }
}

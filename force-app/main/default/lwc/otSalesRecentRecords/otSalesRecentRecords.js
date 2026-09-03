import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRecentRecords from '@salesforce/apex/OtSalesDashboardController.getRecentRecords';

export default class OtSalesRecentRecords extends NavigationMixin(LightningElement) {
    records = [];

    @wire(getRecentRecords)
    wiredData({ data }) {
        if (data) this.records = data;
    }

    get hasRecords() { return this.records.length > 0; }

    handleNavigate(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Account', actionName: 'list' }
        });
    }
}
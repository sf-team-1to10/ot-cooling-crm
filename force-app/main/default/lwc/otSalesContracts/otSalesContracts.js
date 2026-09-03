import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getContracts from '@salesforce/apex/OtSalesDashboardController.getContracts';

export default class OtSalesContracts extends NavigationMixin(LightningElement) {
    contracts = [];

    @wire(getContracts)
    wiredData({ data }) {
        if (data) {
            this.contracts = data.map(c => ({
                ...c,
                endDateFormatted: this._fmtDate(c.endDate)
            }));
        }
    }

    get hasContracts() { return this.contracts.length > 0; }

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
            attributes: { objectApiName: 'ServiceContract', actionName: 'list' }
        });
    }

    _fmtDate(isoStr) {
        if (!isoStr) return '—';
        const parts = isoStr.split('-');
        return `${parts[1]}/${parts[2]}`;
    }
}
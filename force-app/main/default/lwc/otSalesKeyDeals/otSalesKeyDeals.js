import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getKeyDeals from '@salesforce/apex/OtSalesDashboardController.getKeyDeals';

const KRW = new Intl.NumberFormat('ko-KR', { style: 'currency', currency: 'KRW', maximumFractionDigits: 0 });

export default class OtSalesKeyDeals extends NavigationMixin(LightningElement) {
    deals = [];

    @wire(getKeyDeals)
    wiredData({ data }) {
        if (data) {
            this.deals = data.map(d => {
                const prob = d.probability != null ? d.probability : 0;
                return {
                    ...d,
                    detail: `${d.amount != null ? KRW.format(d.amount) : '—'} · ${d.stage || '—'} · ${this._fmtDate(d.closeDate)}`,
                    probability: prob,
                    pctStyle: `width: ${prob}%`
                };
            });
        }
    }

    get hasDeals() { return this.deals.length > 0; }

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
            attributes: { objectApiName: 'Opportunity', actionName: 'list' }
        });
    }

    _fmtDate(isoStr) {
        if (!isoStr) return '—';
        const parts = isoStr.split('-');
        return `${parts[1]}/${parts[2]}`;
    }
}
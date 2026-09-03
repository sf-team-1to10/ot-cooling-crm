import { LightningElement, wire } from 'lwc';
import getPipeline from '@salesforce/apex/OtSalesDashboardController.getPipeline';

const KRW = new Intl.NumberFormat('ko-KR', { style: 'currency', currency: 'KRW', maximumFractionDigits: 0 });
const STAGE_ORDER = ['Qualification', 'Proposal', 'Negotiation', 'Closed Won'];
const STAGE_COLORS = {
    'Qualification': '#c9d5e5',
    'Proposal': '#7189af',
    'Negotiation': '#032d60',
    'Closed Won': '#014486'
};

export default class OtSalesPipeline extends LightningElement {
    stages = [];
    total = 0;

    @wire(getPipeline)
    wiredData({ data }) {
        if (data) {
            this.total = typeof data.total === 'number' ? data.total : 0;
            const stageList = data._stages || STAGE_ORDER;
            this.stages = stageList
                .filter(s => data[s] != null && typeof data[s] === 'object')
                .map(s => {
                    const info = data[s];
                    const amt = info.amount || 0;
                    const pct = info.pct || 0;
                    const maxW = Math.max(pct, 5);
                    return {
                        stage: s,
                        amount: amt,
                        amountFormatted: KRW.format(amt),
                        pct: pct,
                        barStyle: `width:${maxW}%;background:${STAGE_COLORS[s] || '#032d60'}`
                    };
                });
        }
    }

    get hasStages() { return this.stages.length > 0; }
    get totalFormatted() { return KRW.format(this.total); }
}
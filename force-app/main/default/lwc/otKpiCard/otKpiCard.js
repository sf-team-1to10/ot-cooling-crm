import { LightningElement, wire } from 'lwc';
import getKpiSummary from '@salesforce/apex/OtKpiCardController.getKpiSummary';

export default class OtKpiCard extends LightningElement {
    kpi = {};
    error;
    isLoading = true;

    @wire(getKpiSummary)
    wiredKpi({ data, error }) {
        if (data) {
            this.kpi = data;
            this.isLoading = false;
        } else if (error) {
            this.error = error;
            this.isLoading = false;
        }
    }
}

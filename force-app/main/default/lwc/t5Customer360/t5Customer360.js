import { LightningElement, api, wire } from 'lwc';
import getCustomer360 from '@salesforce/apex/T5Customer360Controller.getCustomer360';

export default class T5Customer360 extends LightningElement {
    @api recordId;

    data;
    error;

    @wire(getCustomer360, { caseId: '$recordId' })
    wiredData({ data, error }) {
        if (data) {
            this.data = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.data = undefined;
        }
    }

    get isLoading() {
        return !this.data && !this.error;
    }

    get errorMessage() {
        if (!this.error) {
            return '';
        }
        return this.error.body?.message || 'Customer 360 데이터를 불러오지 못했습니다.';
    }

    get accountName() {
        return this.data?.accountName || '고객사 정보 없음';
    }

    get contracts() {
        return (this.data?.contracts || []).map((c) => ({
            ...c,
            itemClass: c.isCurrent
                ? 'slds-item section-row is-current'
                : 'slds-item section-row',
            badgeLabel: c.isExpired ? '만료' : '유효',
            badgeClass: c.isExpired
                ? 'slds-badge slds-theme_error'
                : 'slds-badge slds-theme_success'
        }));
    }

    get assets() {
        return this.data?.assets || [];
    }

    get pastCases() {
        return this.data?.pastCases || [];
    }

    get opportunities() {
        return (this.data?.opportunities || []).map((o) => ({
            ...o,
            badgeLabel: o.isWon ? '수주' : o.stageName,
            badgeClass: o.isWon
                ? 'slds-badge slds-theme_success'
                : 'slds-badge'
        }));
    }

    get hasContracts() {
        return this.contracts.length > 0;
    }

    get hasAssets() {
        return this.assets.length > 0;
    }

    get hasPastCases() {
        return this.pastCases.length > 0;
    }

    get hasOpportunities() {
        return this.opportunities.length > 0;
    }
}

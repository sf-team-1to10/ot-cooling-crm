import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Name';
import getSalesHome from '@salesforce/apex/T5SalesHomeController.getSalesHome';

export default class OtSalesHome extends NavigationMixin(LightningElement) {
    userName;
    tasks = [];
    opportunities = [];

    @wire(getRecord, { recordId: USER_ID, fields: [NAME_FIELD] })
    wiredUser({ data }) {
        if (data) {
            this.userName = getFieldValue(data, NAME_FIELD);
        }
    }

    @wire(getSalesHome)
    wiredHome({ data }) {
        if (!data) return;
        this.tasks = data.tasks || [];
        this.opportunities = (data.opportunities || []).map(o => ({
            ...o,
            amountFormatted: o.amount != null
                ? new Intl.NumberFormat('ko-KR', { style: 'currency', currency: 'KRW', maximumFractionDigits: 0 }).format(o.amount)
                : '—'
        }));
    }

    get greetingLine() {
        return this.userName ? `${this.userName}님, 안녕하세요` : '안녕하세요';
    }

    get taskCount() {
        return this.tasks.length;
    }

    get oppCount() {
        return this.opportunities.length;
    }

    get hasTasks() {
        return this.tasks.length > 0;
    }

    get hasOpportunities() {
        return this.opportunities.length > 0;
    }

    handleOpenRecord(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }
}

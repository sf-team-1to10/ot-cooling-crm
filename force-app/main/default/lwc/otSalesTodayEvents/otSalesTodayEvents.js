import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTodayEvents from '@salesforce/apex/OtSalesSidebarController.getTodayEvents';

export default class OtSalesTodayEvents extends NavigationMixin(LightningElement) {
    events = [];

    @wire(getTodayEvents)
    wiredData({ data }) {
        if (data) this.events = data;
    }

    get hasEvents() { return this.events.length > 0; }

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
            attributes: { objectApiName: 'Event', actionName: 'list' }
        });
    }
}
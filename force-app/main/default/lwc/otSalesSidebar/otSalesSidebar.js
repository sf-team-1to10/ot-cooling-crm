import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTodayTasks from '@salesforce/apex/OtSalesSidebarController.getTodayTasks';
import getTodayEvents from '@salesforce/apex/OtSalesSidebarController.getTodayEvents';
import { getListUi } from 'lightning/uiListApi';

export default class OtSalesSidebar extends NavigationMixin(LightningElement) {
    tasks = [];
    events = [];
    recentItems = [];

    @wire(getTodayTasks)
    wiredTasks({ data }) {
        if (data) this.tasks = data;
    }

    @wire(getTodayEvents)
    wiredEvents({ data }) {
        if (data) this.events = data;
    }

    get hasTasks() { return this.tasks.length > 0; }
    get hasEvents() { return this.events.length > 0; }

    handleNavigate(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    handleViewAllTasks() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Task', actionName: 'list' },
            state: { filterName: 'OpenTasks' }
        });
    }
}
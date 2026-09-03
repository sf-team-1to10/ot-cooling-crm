import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTodayTasks from '@salesforce/apex/OtSalesSidebarController.getTodayTasks';

export default class OtSalesTodayTasks extends NavigationMixin(LightningElement) {
    tasks = [];

    @wire(getTodayTasks)
    wiredData({ data }) {
        if (data) this.tasks = data;
    }

    get hasTasks() { return this.tasks.length > 0; }

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
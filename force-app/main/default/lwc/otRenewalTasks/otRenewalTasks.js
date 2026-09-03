import { LightningElement } from 'lwc';

export default class OtRenewalTasks extends LightningElement {
    activeView = 'tasks';
    selectedTask = 'renewal';
    opportunityCreated = false;

    get isTasksView() { return this.activeView === 'tasks'; }
    get isContractView() { return this.activeView === 'contract'; }

    get tasksTabClass() { return this.activeView === 'tasks' ? 'ren-tab on' : 'ren-tab'; }
    get contractTabClass() { return this.activeView === 'contract' ? 'ren-tab on' : 'ren-tab'; }

    handleShowTasks() { this.activeView = 'tasks'; }
    handleShowContract() { this.activeView = 'contract'; }

    handleSelectTask(event) {
        this.selectedTask = event.currentTarget.dataset.task;
    }

    get isRenewalSelected() { return this.selectedTask === 'renewal'; }

    get renewalRowClass() {
        return this.selectedTask === 'renewal' ? 'rl-row rl-row-selected' : 'rl-row';
    }

    handleCreateOpportunity() {
        this.opportunityCreated = true;
    }
}

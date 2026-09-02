import { LightningElement } from 'lwc';

export default class OtRenewalTasks extends LightningElement {
    selectedTask = 'renewal';

    handleSelectTask(event) {
        this.selectedTask = event.currentTarget.dataset.task;
    }

    get isRenewalSelected() {
        return this.selectedTask === 'renewal';
    }

    get renewalRowClass() {
        return this.selectedTask === 'renewal' ? 'rl-row rl-row-selected' : 'rl-row';
    }
}

import { LightningElement, wire } from 'lwc';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    focusTab
} from 'lightning/platformWorkspaceApi';

export default class OtRenewalTasks extends LightningElement {
    selectedTask = 'renewal';

    @wire(IsConsoleNavigation) isConsoleNavigation;

    get isConsole() {
        return this.isConsoleNavigation?.data === true;
    }

    handleSelectTask(event) {
        this.selectedTask = event.currentTarget.dataset.task;
    }

    get isRenewalSelected() {
        return this.selectedTask === 'renewal';
    }

    get renewalRowClass() {
        return this.selectedTask === 'renewal' ? 'rl-row rl-row-selected' : 'rl-row';
    }

    async handleOpenContract() {
        if (this.isConsole) {
            const focused = await getFocusedTabInfo();
            const parentTabId = focused.tabId;
            const pageReference = {
                type: 'standard__component',
                attributes: { componentName: 'c__otServiceContractReview' }
            };
            const subtabId = await openSubtab({ parentTabId, pageReference, focus: true });
            await focusTab(subtabId);
        }
    }
}

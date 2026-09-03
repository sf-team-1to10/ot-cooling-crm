import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    focusTab
} from 'lightning/platformWorkspaceApi';
import CASE_FIELD from '@salesforce/schema/MessagingSession.CaseId';

export default class OtCaseSubtabOpener extends LightningElement {
    @api recordId;
    _opened = false;

    @wire(IsConsoleNavigation) isConsole;

    @wire(getRecord, { recordId: '$recordId', fields: [CASE_FIELD] })
    wiredRecord({ data }) {
        if (!data || this._opened) return;
        const caseId = getFieldValue(data, CASE_FIELD);
        if (caseId) {
            this._opened = true;
            this._openCaseSubtab(caseId);
        }
    }

    async _openCaseSubtab(caseId) {
        if (!this.isConsole) return;
        try {
            const focused = await getFocusedTabInfo();
            const parentTabId = focused.parentTabId || focused.tabId;
            const pageReference = {
                type: 'standard__recordPage',
                attributes: {
                    recordId: caseId,
                    objectApiName: 'Case',
                    actionName: 'view'
                }
            };
            const subtabId = await openSubtab({
                parentTabId,
                pageReference,
                focus: true
            });
            await focusTab(subtabId);
        } catch (_) {
            // not in console context
        }
    }
}

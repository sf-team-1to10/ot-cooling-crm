import { LightningElement, api } from 'lwc';

export default class T5CaseIntakePanel extends LightningElement {
    @api recordId;
    @api caseId;

    get effectiveRecordId() {
        return this.caseId || this.recordId;
    }
}
import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import CASE_NUMBER from '@salesforce/schema/Case.CaseNumber';

export default class OtBriefingNavigator extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: [CASE_NUMBER] })
    caseRecord;

    get caseNumber() {
        return getFieldValue(this.caseRecord.data, CASE_NUMBER);
    }

    handleOpen() {
    }
}
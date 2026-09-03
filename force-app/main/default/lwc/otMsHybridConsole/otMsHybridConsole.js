import { LightningElement, api, wire } from 'lwc';
import getCaseId from '@salesforce/apex/OTMsSessionResolver.getCaseId';

export default class OtMsHybridConsole extends LightningElement {
    @api recordId;

    caseId;
    resolveError;

    @wire(getCaseId, { recordId: '$recordId' })
    wiredCaseId({ data, error }) {
        if (data) {
            this.caseId = data;
            this.resolveError = undefined;
        } else if (error) {
            this.resolveError = error;
            this.caseId = undefined;
        }
    }

    get isResolved() {
        return !!this.caseId;
    }

    get isResolving() {
        return !this.caseId && !this.resolveError;
    }

    get resolveErrorMessage() {
        return this.resolveError?.body?.message || 'MessagingSession에서 Case를 찾을 수 없습니다.';
    }

}

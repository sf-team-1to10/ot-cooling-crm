import { LightningElement } from 'lwc';

export default class OtServiceContractReview extends LightningElement {
    opportunityCreated = false;

    handleCreateOpportunity() {
        this.opportunityCreated = true;
    }
}

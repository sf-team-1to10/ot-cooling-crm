import { LightningElement, api, track } from 'lwc';

export default class OtServiceRequestModal extends LightningElement {
    @api isOpen = false;
    @track symptom = '';
    @track memo = '';

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
    handleGoDetail() {
        this.dispatchEvent(new CustomEvent('godetail'));
    }
    handleBackdrop(event) {
        if (event.target === event.currentTarget) {
            this.handleClose();
        }
    }
    handleSymptom(event) {
        this.symptom = event.target.value;
    }
    handleMemo(event) {
        this.memo = event.target.value;
    }
    handleSubmit() {
        this.symptom = '';
        this.memo = '';
        this.dispatchEvent(new CustomEvent('close'));
    }
}

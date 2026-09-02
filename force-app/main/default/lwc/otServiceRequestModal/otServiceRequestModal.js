import { LightningElement, api } from 'lwc';

export default class OtServiceRequestModal extends LightningElement {
    @api isOpen = false;

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
}
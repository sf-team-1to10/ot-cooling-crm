import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Name';
import ACCOUNT_NAME_FIELD from '@salesforce/schema/User.Contact.Account.Name';

// Top navigation header for the OT customer portal. The logged-in user's
// name/company are read from the running user's record (never hardcoded).
export default class OtPortalHeader extends LightningElement {
    // Which menu item is highlighted: 'assets' | 'intake'. Set per page.
    @api activePage = 'assets';

    userName;
    companyName;

    @wire(getRecord, {
        recordId: USER_ID,
        fields: [NAME_FIELD, ACCOUNT_NAME_FIELD]
    })
    wiredUser({ data }) {
        if (data) {
            this.userName = getFieldValue(data, NAME_FIELD);
            this.companyName = getFieldValue(data, ACCOUNT_NAME_FIELD);
        }
    }

    get meLabel() {
        if (this.userName && this.companyName) {
            return `${this.userName} · ${this.companyName}`;
        }
        return this.userName || '';
    }

    get assetsClass() {
        return this.activePage === 'assets' ? 'nav-item is-on' : 'nav-item';
    }

    get intakeClass() {
        return this.activePage === 'intake' ? 'nav-item is-on' : 'nav-item';
    }

    handleAssets() {
        this.dispatchEvent(new CustomEvent('navigate', { detail: 'assets' }));
    }

    handleIntake() {
        this.dispatchEvent(new CustomEvent('navigate', { detail: 'intake' }));
    }
}

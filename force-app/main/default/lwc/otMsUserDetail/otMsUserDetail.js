import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSessionInfo from '@salesforce/apex/OtMsInfoPanelController.getSessionInfo';

const CONSENT_OPTED_IN = new Set(['ImplicitlyOptedIn', 'OptedIn', 'ExplicitlyOptedIn']);

export default class OtMsUserDetail extends NavigationMixin(LightningElement) {
    @api recordId;

    info;
    error;

    @wire(getSessionInfo, { sessionId: '$recordId' })
    wired({ data, error }) {
        if (data)  { this.info = data;  this.error = undefined; }
        if (error) { this.error = error; this.info = undefined; }
    }

    get isLoading()    { return !this.info && !this.error; }
    get hasError()     { return !!this.error; }
    get errorMessage() { return this.error?.body?.message || 'Messaging User 정보를 불러오지 못했습니다.'; }

    get consentClass() {
        return CONSENT_OPTED_IN.has(this.info?.endUserConsentStatus)
            ? 'ms-badge ms-badge--active'
            : 'ms-badge ms-badge--ended';
    }

    get consentLabel() {
        const c = this.info?.endUserConsentStatus;
        if (!c) return '—';
        const map = {
            ImplicitlyOptedIn:  'Implicitly Opted In',
            ExplicitlyOptedIn:  'Explicitly Opted In',
            OptedIn:            'Opted In',
            OptedOut:           'Opted Out',
            NotSet:             'Not Set'
        };
        return map[c] || c;
    }

    get endUserAccountDisplay() {
        return this.info?.endUserAccountName || '—';
    }

    get contactUrl()          { return this.info?.contactId ? '/' + this.info.contactId : '#'; }
    get contactPhoneDisplay() { return this.info?.contactPhone || '—'; }
    get contactEmailDisplay() { return this.info?.contactEmail || '—'; }

    handleContactClick(event) {
        event.preventDefault();
        if (!this.info?.contactId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.info.contactId, objectApiName: 'Contact', actionName: 'view' }
        });
    }
}

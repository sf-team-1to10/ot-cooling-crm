import { LightningElement, api } from 'lwc';
import LOGO from '@salesforce/resourceUrl/OT_Logo_KR';
import COOLBIT_MONITOR from '@salesforce/resourceUrl/OT_Coolbit_Monitor';

export default class OtEquipSidebar extends LightningElement {
    @api activeNav = 'equipment';
    @api customerName = '';
    @api contactName = '';
    @api contactRole = '';

    get hasCustomerInfo() { return !!this.customerName; }
    get logoUrl() { return LOGO; }
    get coolbitMonitorUrl() { return COOLBIT_MONITOR; }

    get overviewClass()    { return this.navClass('overview'); }
    get equipmentClass()   { return this.navClass('equipment'); }
    get alarmsClass()      { return this.navClass('alarms'); }
    get analyticsClass()   { return this.navClass('analytics'); }
    get reportsClass()     { return this.navClass('reports'); }
    get maintenanceClass() { return this.navClass('maintenance'); }
    get settingsClass()    { return this.navClass('settings'); }

    navClass(key) {
        return this.activeNav === key ? 'nav-item nav-item--active' : 'nav-item';
    }

    handleNavClick(event) {
        const page = event.currentTarget.dataset.page;
        this.dispatchEvent(new CustomEvent('navigate', { detail: { page } }));
    }

    handleAssistClick() {
        this.dispatchEvent(new CustomEvent('navigate', { detail: { page: 'assistant' } }));
    }
}
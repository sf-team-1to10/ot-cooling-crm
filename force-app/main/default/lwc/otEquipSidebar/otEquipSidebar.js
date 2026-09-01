import { LightningElement, api } from 'lwc';

export default class OtEquipSidebar extends LightningElement {
    @api activeNav = 'assets';
    @api customerName = '';
    @api contactName = '';
    @api contactRole = '';

    get hasCustomerInfo() {
        return !!this.customerName;
    }

    get overviewClass() {
        return this.activeNav === 'overview' ? 'nav-item nav-item--active' : 'nav-item';
    }

    get assetsClass() {
        return this.activeNav === 'assets' ? 'nav-item nav-item--active' : 'nav-item';
    }

    get faultsClass() {
        return this.activeNav === 'faults' ? 'nav-item nav-item--active' : 'nav-item';
    }

    get changesClass() {
        return this.activeNav === 'changes' ? 'nav-item nav-item--active' : 'nav-item';
    }

    get acceptanceClass() {
        return this.activeNav === 'acceptance' ? 'nav-item nav-item--active' : 'nav-item';
    }

    get maintenanceClass() {
        return this.activeNav === 'maintenance' ? 'nav-item nav-item--active' : 'nav-item';
    }

    get settingsClass() {
        return this.activeNav === 'settings' ? 'nav-item nav-item--active' : 'nav-item';
    }

    handleNavClick(event) {
        const page = event.currentTarget.dataset.page;
        this.dispatchEvent(new CustomEvent('navigate', { detail: { page } }));
    }

    handleAssistClick() {
        this.dispatchEvent(new CustomEvent('navigate', { detail: { page: 'assistant' } }));
    }
}
import { LightningElement, api } from 'lwc';

export default class OtPortalSidebar extends LightningElement {
    @api activePage = 'overview';
    @api attentionCount = 0;

    get hasAttention() {
        return this.attentionCount > 0;
    }

    get overviewClass()     { return this.itemClass('overview'); }
    get assetsClass()       { return this.itemClass('assets'); }
    get intakeClass()       { return this.itemClass('intake'); }
    get changeClass()       { return this.itemClass('change') + ' disabled'; }
    get maintenanceClass()  { return this.itemClass('maintenance') + ' disabled'; }

    itemClass(page) {
        return 'menu-btn' + (this.activePage === page ? ' is-on' : '');
    }

    handleNav(event) {
        const page = event.currentTarget.dataset.page;
        if (page === 'change' || page === 'maintenance') return;
        this.dispatchEvent(new CustomEvent('navigate', { detail: page }));
    }
}

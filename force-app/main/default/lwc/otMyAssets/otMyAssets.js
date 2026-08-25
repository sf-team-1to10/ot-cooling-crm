import { LightningElement, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import ACCOUNT_NAME_FIELD from '@salesforce/schema/User.Contact.Account.Name';
import getMyAssets from '@salesforce/apex/OTMyAssetsController.getMyAssets';

export default class OtMyAssets extends LightningElement {
    assets = [];
    error;
    isLoading = true;
    companyName;
    filter = 'all'; // 'all' | 'attention'

    @wire(getRecord, {
        recordId: USER_ID,
        fields: [ACCOUNT_NAME_FIELD]
    })
    wiredUser({ data }) {
        if (data) {
            this.companyName = getFieldValue(data, ACCOUNT_NAME_FIELD);
        }
    }

    @wire(getMyAssets)
    wiredAssets({ data, error }) {
        if (data) {
            this.assets = data;
            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.assets = [];
            this.error = this.reduceError(error);
            this.isLoading = false;
        }
    }

    // Presentation-only view models. Alert level is derived from the real
    // Open_Items_Summary__c value already returned by the controller — no new
    // query or field is introduced.
    get decoratedAssets() {
        return this.assets.map((a) => {
            const open = Number(a.openItemsSummary) || 0;
            const attention = open > 0;
            return {
                ...a,
                attention,
                statusText: attention ? '● 주의' : '● 정상',
                statusClass: attention ? 'st warn' : 'st ok',
                subline: this.buildSubline(a)
            };
        });
    }

    get visibleAssets() {
        if (this.filter === 'attention') {
            return this.decoratedAssets.filter((a) => a.attention);
        }
        return this.decoratedAssets;
    }

    buildSubline(a) {
        const parts = [];
        if (a.productName) {
            parts.push(a.productName);
        }
        if (a.serialNumber) {
            parts.push(`S/N ${a.serialNumber}`);
        }
        if (a.status) {
            parts.push(a.status);
        }
        return parts.join(' · ');
    }

    get allCount() {
        return this.assets.length;
    }

    get attentionCount() {
        return this.decoratedAssets.filter((a) => a.attention).length;
    }

    get subheading() {
        const count = `${this.allCount}대`;
        return this.companyName ? `${this.companyName} · ${count}` : count;
    }

    get allPillClass() {
        return this.filter === 'all' ? 'pill is-on' : 'pill';
    }

    get attentionPillClass() {
        return this.filter === 'attention' ? 'pill is-on' : 'pill';
    }

    // The user owns at least one asset (drives whether pills/filter show).
    get hasAnyAssets() {
        return this.assets.length > 0;
    }

    // The current filter has at least one matching asset.
    get hasVisibleAssets() {
        return this.visibleAssets.length > 0;
    }

    // No assets at all for this user (distinct from a filter with 0 matches).
    get showEmptyState() {
        return !this.isLoading && !this.error && !this.hasAnyAssets;
    }

    // A filter is active but matched nothing; keep pills, swap the list body.
    get showNoMatch() {
        return (
            !this.isLoading &&
            !this.error &&
            this.hasAnyAssets &&
            !this.hasVisibleAssets
        );
    }

    handleShowAll() {
        this.filter = 'all';
    }

    handleShowAttention() {
        this.filter = 'attention';
    }

    handleContact(event) {
        const { id, name } = event.currentTarget.dataset;
        this.dispatchEvent(
            new CustomEvent('contact', {
                detail: { assetId: id, assetName: name }
            })
        );
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || '알 수 없는 오류가 발생했습니다.';
    }
}

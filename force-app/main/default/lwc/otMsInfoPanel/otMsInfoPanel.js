import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    focusTab
} from 'lightning/platformWorkspaceApi';
import getSessionInfo from '@salesforce/apex/OtMsInfoPanelController.getSessionInfo';

const STATUS_ACTIVE  = 'Active';
const STATUS_WAITING = 'Waiting';
const STATUS_ENDED   = 'Ended';

export default class OtMsInfoPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    info;
    error;
    activeTab = 0;

    @wire(IsConsoleNavigation) isConsole;

    @wire(getSessionInfo, { sessionId: '$recordId' })
    wiredInfo({ data, error }) {
        if (data) {
            this.info  = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.info  = undefined;
        }
    }

    // ── loading / error ──────────────────────────────────────────────────
    get isLoading() {
        return !this.info && !this.error;
    }

    get hasError() {
        return !!this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || '세션 정보를 불러오지 못했습니다.';
    }

    // ── derived display values ────────────────────────────────────────────
    get sessionTitle() {
        return this.info?.endUserName
            ? this.info.endUserName + ' 와의 대화'
            : 'Guest 와의 대화';
    }

    get statusBadgeClass() {
        const s = this.info?.status;
        if (s === STATUS_ACTIVE || s === STATUS_WAITING) {
            return 'slds-badge ms-badge ms-badge--active';
        }
        if (s === STATUS_ENDED) {
            return 'slds-badge ms-badge ms-badge--ended';
        }
        return 'slds-badge ms-badge';
    }

    get consentBadgeClass() {
        const c = this.info?.endUserConsentStatus;
        if (c === 'ImplicitlyOptedIn' || c === 'OptedIn') {
            return 'slds-badge ms-badge ms-badge--active';
        }
        return 'slds-badge ms-badge ms-badge--ended';
    }

    get startTimeText() {
        return this._fmt(this.info?.startTime);
    }

    get endTimeText() {
        return this._fmt(this.info?.endTime);
    }

    get caseUrl() {
        return this.info?.caseId ? '/' + this.info.caseId : '#';
    }

    get contactUrl() {
        return this.info?.contactId ? '/' + this.info.contactId : '#';
    }

    // ── tab helpers ───────────────────────────────────────────────────────
    get isTab0() { return this.activeTab === 0; }
    get isTab1() { return this.activeTab === 1; }
    get isTab2() { return this.activeTab === 2; }

    get tab0Class() { return this._tabClass(0); }
    get tab1Class() { return this._tabClass(1); }
    get tab2Class() { return this._tabClass(2); }

    _tabClass(idx) {
        return 'ms-tab-btn' + (this.activeTab === idx ? ' ms-tab-btn--active' : '');
    }

    handleTabClick(event) {
        this.activeTab = Number(event.currentTarget.dataset.idx);
    }

    // ── navigation ────────────────────────────────────────────────────────
    handleCaseClick(event) {
        event.preventDefault();
        if (this.info?.caseId) {
            this._navigateToRecord(this.info.caseId, 'Case');
        }
    }

    handleContactClick(event) {
        event.preventDefault();
        if (this.info?.contactId) {
            this._navigateToRecord(this.info.contactId, 'Contact');
        }
    }

    handleOpenCaseSubtab() {
        if (this.info?.caseId) {
            this._openSubtab(this.info.caseId, 'Case');
        }
    }

    handleNewCase() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Case',
                actionName:    'new'
            }
        });
    }

    async _openSubtab(recordId, objectApiName) {
        if (!this.isConsole) {
            this._navigateToRecord(recordId, objectApiName);
            return;
        }
        try {
            const focused     = await getFocusedTabInfo();
            const parentTabId = focused.parentTabId || focused.tabId;
            const pageRef     = {
                type: 'standard__recordPage',
                attributes: { recordId, objectApiName, actionName: 'view' }
            };
            const subtabId = await openSubtab({ parentTabId, pageReference: pageRef, focus: true });
            await focusTab(subtabId);
        } catch (_) {
            this._navigateToRecord(recordId, objectApiName);
        }
    }

    _navigateToRecord(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName, actionName: 'view' }
        });
    }

    _fmt(raw) {
        if (!raw) return '—';
        return new Date(raw).toLocaleString('ko-KR', {
            month:  '2-digit',
            day:    '2-digit',
            hour:   '2-digit',
            minute: '2-digit'
        });
    }
}

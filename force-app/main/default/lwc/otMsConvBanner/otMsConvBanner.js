import { LightningElement, api, wire, track } from 'lwc';
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
const TICK_MS        = 30000;

export default class OtMsConvBanner extends NavigationMixin(LightningElement) {
    @api recordId;

    info;
    @track elapsed = '—';
    _timer;

    @wire(IsConsoleNavigation) isConsole;

    @wire(getSessionInfo, { sessionId: '$recordId' })
    wired({ data, error }) {
        if (data) {
            this.info = data;
            this._startTick();
        }
        if (error) { this.info = undefined; }
    }

    disconnectedCallback() {
        this._stopTick();
    }

    // ── elapsed ticker ────────────────────────────────────────────────
    _startTick() {
        this._tick();
        this._stopTick();
        if (this.info?.status === STATUS_ACTIVE || this.info?.status === STATUS_WAITING) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._timer = setInterval(() => this._tick(), TICK_MS);
        }
    }

    _stopTick() {
        if (this._timer) {
            clearInterval(this._timer);
            this._timer = null;
        }
    }

    _tick() {
        if (!this.info?.startTime) { this.elapsed = '—'; return; }
        const end   = this.info.endTime ? new Date(this.info.endTime) : new Date();
        const diffMin = Math.round((end - new Date(this.info.startTime)) / 60000);
        if (diffMin < 60) {
            this.elapsed = diffMin + '분';
        } else {
            const h = Math.floor(diffMin / 60);
            const m = diffMin % 60;
            this.elapsed = m === 0 ? h + '시간' : h + '시간 ' + m + '분';
        }
    }

    // ── display helpers ────────────────────────────────────────────────
    get displayName() {
        return this.info?.endUserName || 'Guest';
    }

    get avatarInitial() {
        const n = this.info?.endUserName;
        return n ? n.charAt(0).toUpperCase() : 'G';
    }

    get statusLabel() {
        const s = this.info?.status;
        if (s === STATUS_ACTIVE)  return '상담 중';
        if (s === STATUS_WAITING) return '대기 중';
        if (s === STATUS_ENDED)   return '종료';
        return s || '—';
    }

    get statusClass() {
        const s = this.info?.status;
        if (s === STATUS_ACTIVE || s === STATUS_WAITING) return 'status-dot status-dot--active';
        if (s === STATUS_ENDED) return 'status-dot status-dot--ended';
        return 'status-dot';
    }

    get startTimeText() {
        if (!this.info?.startTime) return '—';
        return new Date(this.info.startTime).toLocaleString('ko-KR', {
            month: '2-digit', day: '2-digit',
            hour: '2-digit', minute: '2-digit'
        });
    }

    get caseUrl() { return this.info?.caseId ? '/' + this.info.caseId : '#'; }

    handleCaseClick(event) {
        event.preventDefault();
        if (!this.info?.caseId) return;
        this._openSubtab(this.info.caseId);
    }

    async _openSubtab(caseId) {
        if (!this.isConsole?.data) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: caseId, objectApiName: 'Case', actionName: 'view' }
            });
            return;
        }
        try {
            const focused     = await getFocusedTabInfo();
            const parentTabId = focused.parentTabId || focused.tabId;
            const subtabId    = await openSubtab({
                parentTabId,
                pageReference: {
                    type: 'standard__recordPage',
                    attributes: { recordId: caseId, objectApiName: 'Case', actionName: 'view' }
                },
                focus: true
            });
            await focusTab(subtabId);
        } catch (_) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: caseId, objectApiName: 'Case', actionName: 'view' }
            });
        }
    }
}

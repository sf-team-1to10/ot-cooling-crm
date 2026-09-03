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
const CONSENT_IN     = new Set(['ImplicitlyOptedIn', 'OptedIn', 'ExplicitlyOptedIn']);
const CONSENT_LABELS = {
    ImplicitlyOptedIn:  '묵시적 동의',
    ExplicitlyOptedIn:  '명시적 동의',
    OptedIn:            '동의',
    OptedOut:           '미동의',
    NotSet:             '미설정'
};

export default class OtMsDetail extends NavigationMixin(LightningElement) {
    @api recordId;

    info;
    error;
    _open = [true, true, true];

    @wire(IsConsoleNavigation) isConsole;

    @wire(getSessionInfo, { sessionId: '$recordId' })
    wired({ data, error }) {
        if (data)  { this.info = data;  this.error = undefined; }
        if (error) { this.error = error; this.info = undefined; }
    }

    // ── loading / error ────────────────────────────────────────────────
    get isLoading()    { return !this.info && !this.error; }
    get hasError()     { return !!this.error; }
    get errorMessage() { return this.error?.body?.message || '세션 정보를 불러오지 못했습니다.'; }

    // ── accordion ─────────────────────────────────────────────────────
    get open0() { return this._open[0]; }
    get open1() { return this._open[1]; }
    get open2() { return this._open[2]; }
    get chevron0() { return this._open[0] ? 'utility:chevrondown' : 'utility:chevronright'; }
    get chevron1() { return this._open[1] ? 'utility:chevrondown' : 'utility:chevronright'; }
    get chevron2() { return this._open[2] ? 'utility:chevrondown' : 'utility:chevronright'; }

    toggle0() { this._open = [!this._open[0], this._open[1], this._open[2]]; }
    toggle1() { this._open = [this._open[0], !this._open[1], this._open[2]]; }
    toggle2() { this._open = [this._open[0], this._open[1], !this._open[2]]; }

    // ── 세션 ──────────────────────────────────────────────────────────
    get statusLabel() {
        const s = this.info?.status;
        if (s === STATUS_ACTIVE)  return '상담 중';
        if (s === STATUS_WAITING) return '대기 중';
        if (s === STATUS_ENDED)   return '종료';
        return s || '—';
    }

    get statusClass() {
        const s = this.info?.status;
        if (s === STATUS_ACTIVE || s === STATUS_WAITING) return 'badge badge--green';
        if (s === STATUS_ENDED) return 'badge badge--gray';
        return 'badge';
    }

    get startTimeText() { return this._fmt(this.info?.startTime); }
    get endTimeText()   { return this._fmt(this.info?.endTime); }

    get durationText() {
        if (!this.info?.startTime) return '—';
        const end   = this.info.endTime ? new Date(this.info.endTime) : new Date();
        const min   = Math.round((end - new Date(this.info.startTime)) / 60000);
        if (min < 60) return min + '분';
        const h = Math.floor(min / 60), m = min % 60;
        return m === 0 ? h + '시간' : h + '시간 ' + m + '분';
    }

    // ── 고객 ──────────────────────────────────────────────────────────
    get consentLabel() {
        const c = this.info?.endUserConsentStatus;
        return CONSENT_LABELS[c] || c || '—';
    }

    get consentClass() {
        return CONSENT_IN.has(this.info?.endUserConsentStatus)
            ? 'badge badge--green'
            : 'badge badge--gray';
    }

    get endUserAccountDisplay() { return this.info?.endUserAccountName || '—'; }
    get contactUrl()            { return this.info?.contactId ? '/' + this.info.contactId : '#'; }
    get contactPhoneDisplay()   { return this.info?.contactPhone || '—'; }
    get contactEmailDisplay()   { return this.info?.contactEmail || '—'; }

    handleContactClick(event) {
        event.preventDefault();
        if (!this.info?.contactId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.info.contactId, objectApiName: 'Contact', actionName: 'view' }
        });
    }

    // ── Case ──────────────────────────────────────────────────────────
    get hasCaseId()      { return !!this.info?.caseId; }
    get caseUrl()        { return this.info?.caseId ? '/' + this.info.caseId : '#'; }
    get accountDisplay() { return this.info?.accountName   || '—'; }
    get assetDisplay()   { return this.info?.assetName     || '—'; }
    get caseTypeDisplay()   { return this.info?.caseType   || '—'; }
    get caseReasonDisplay() { return this.info?.caseReason || '—'; }
    get hasSla()         { return !!(this.info?.responseSla || this.info?.recoverySla); }

    get priorityClass() {
        const p = this.info?.casePriority;
        if (p === 'High' || p === 'Critical') return 'badge badge--red';
        if (p === 'Medium') return 'badge badge--orange';
        return 'badge';
    }

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

    handleNewCase() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Case', actionName: 'new' }
        });
    }

    _fmt(raw) {
        if (!raw) return '—';
        return new Date(raw).toLocaleString('ko-KR', {
            month: '2-digit', day: '2-digit',
            hour: '2-digit',  minute: '2-digit'
        });
    }
}

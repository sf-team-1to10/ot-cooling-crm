import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import STATUS_FIELD       from '@salesforce/schema/MessagingSession.Status';
import START_FIELD        from '@salesforce/schema/MessagingSession.StartTime';
import END_FIELD          from '@salesforce/schema/MessagingSession.EndTime';
import ORIGIN_FIELD       from '@salesforce/schema/MessagingSession.Origin';
import CHANNEL_NAME_FIELD from '@salesforce/schema/MessagingSession.ChannelName';
import CHANNEL_KEY_FIELD  from '@salesforce/schema/MessagingSession.ChannelKey';
import CHANNEL_TYPE_FIELD from '@salesforce/schema/MessagingSession.ChannelType';
import END_USER_ID_FIELD  from '@salesforce/schema/MessagingSession.MessagingEndUserId';

const MS_FIELDS = [
    STATUS_FIELD, START_FIELD, END_FIELD, ORIGIN_FIELD,
    CHANNEL_NAME_FIELD, CHANNEL_KEY_FIELD, CHANNEL_TYPE_FIELD,
    END_USER_ID_FIELD
];
const MEU_FIELDS = [
    'MessagingEndUser.Name',
    'MessagingEndUser.MessageType',
    'MessagingEndUser.MessagingPlatformKey',
    'MessagingEndUser.MessagingConsentStatus',
    'MessagingEndUser.Account.Name',
    'MessagingEndUser.Contact.Name',
    'MessagingEndUser.Lead.Name'
];

const STATUS_KO = { Active: '진행 중', Ended: '종료', Waiting: '대기 중', New: '새 대화' };
const ORIGIN_KO = { InboundInitiated: '인바운드', OutboundInitiated: '아웃바운드', Agent: '에이전트' };
const CONSENT_KO = {
    ImplicitlyOptedIn: '묵시적 수신 동의',
    ExplicitlyOptedIn: '명시적 수신 동의',
    OptedOut: '수신 거부',
    NotSet: '미설정'
};

export default class OtMsSidebarLeft extends LightningElement {
    @api recordId;
    _ms = null;
    _meu = null;

    @wire(getRecord, { recordId: '$recordId', fields: MS_FIELDS })
    wiredMs({ data }) { this._ms = data || null; }

    @wire(getRecord, { recordId: '$endUserId', fields: MEU_FIELDS })
    wiredMeu({ data }) { this._meu = data || null; }

    /* ── Session ── */
    get isLoadingMs() { return !this._ms; }
    get status() { return getFieldValue(this._ms, STATUS_FIELD) || ''; }
    get statusLabel() { return STATUS_KO[this.status] || this.status || '—'; }
    get statusBadgeClass() {
        return this.status === 'Active' ? 'badge badge--active' : 'badge badge--ended';
    }

    get channelName() { return getFieldValue(this._ms, CHANNEL_NAME_FIELD) || '—'; }
    get channelType() { return getFieldValue(this._ms, CHANNEL_TYPE_FIELD) || '—'; }
    get channelKey()  { return getFieldValue(this._ms, CHANNEL_KEY_FIELD)  || '—'; }
    get originLabel() {
        const raw = getFieldValue(this._ms, ORIGIN_FIELD);
        return ORIGIN_KO[raw] || raw || '—';
    }
    get startTimeFormatted() { return this._fmt(getFieldValue(this._ms, START_FIELD)); }
    get endTimeFormatted()   { return this._fmt(getFieldValue(this._ms, END_FIELD)); }

    get elapsedLabel() {
        const start = getFieldValue(this._ms, START_FIELD);
        const end   = getFieldValue(this._ms, END_FIELD);
        if (!start) return '—';
        const mins = Math.floor(((end ? new Date(end) : new Date()) - new Date(start)) / 60000);
        if (mins < 1) return '1분 미만';
        return mins < 60 ? `${mins}분` : `${Math.floor(mins / 60)}시간 ${mins % 60}분`;
    }

    _fmt(val) {
        if (!val) return '—';
        return new Date(val).toLocaleString('ko-KR', {
            year: 'numeric', month: 'numeric', day: 'numeric',
            hour: '2-digit', minute: '2-digit'
        });
    }

    /* ── End User ── */
    get endUserId() { return getFieldValue(this._ms, END_USER_ID_FIELD) || null; }
    get isLoadingMeu() { return !!this.endUserId && !this._meu; }

    get meuName()        { return this._meuF('Name')                 || 'Guest'; }
    get meuMessageType() { return this._meuF('MessageType')          || '—'; }
    get meuPlatformKey() { return this._meuF('MessagingPlatformKey') || '—'; }
    get meuAccountName() { return this._meuRel('Account') || '—'; }
    get meuContactName() { return this._meuRel('Contact') || '—'; }
    get meuLeadName()    { return this._meuRel('Lead')    || '—'; }
    get meuConsentStatus() {
        const raw = this._meuF('MessagingConsentStatus');
        return CONSENT_KO[raw] || raw || '—';
    }
    get avatarInitial() {
        const n = this.meuName || 'G';
        return n.trim().charAt(0).toUpperCase();
    }

    _meuF(name) { return this._meu?.fields[name]?.value ?? null; }
    _meuRel(name) { return this._meu?.fields[name]?.value?.fields?.Name?.value ?? null; }
}

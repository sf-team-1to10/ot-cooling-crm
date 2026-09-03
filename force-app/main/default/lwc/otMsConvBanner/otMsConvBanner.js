import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';

import STATUS_FIELD   from '@salesforce/schema/MessagingSession.Status';
import START_FIELD    from '@salesforce/schema/MessagingSession.StartTime';
import END_FIELD      from '@salesforce/schema/MessagingSession.EndTime';
import ORIGIN_FIELD   from '@salesforce/schema/MessagingSession.Origin';
import CHANNEL_FIELD  from '@salesforce/schema/MessagingSession.ChannelName';
import CASE_ID_FIELD  from '@salesforce/schema/MessagingSession.CaseId';
import PREVIEW_FIELD  from '@salesforce/schema/MessagingSession.PreviewDetails';

const FIELDS = [
    STATUS_FIELD, START_FIELD, END_FIELD,
    ORIGIN_FIELD, CHANNEL_FIELD, CASE_ID_FIELD, PREVIEW_FIELD
];

const STATUS_KO = {
    Active:  '진행 중',
    Ended:   '종료',
    Waiting: '대기 중',
    New:     '새 대화',
};

const ORIGIN_KO = {
    InboundInitiated:  '인바운드',
    OutboundInitiated: '아웃바운드',
};

export default class OtMsConvBanner extends NavigationMixin(LightningElement) {
    @api recordId;

    _ms;
    _caseRecord;
    _elapsed;
    _timer;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredMs({ data, error }) {
        if (data) {
            this._ms = data;
            this._startElapsedTimer();
        }
        if (error) this._ms = null;
    }

    /* Case 레코드에서 CaseNumber + Account 이름 가져오기 */
    @wire(getRecord, {
        recordId: '$caseId',
        fields: ['Case.CaseNumber', 'Case.Account.Name']
    })
    wiredCase({ data }) {
        this._caseRecord = data || null;
    }

    /* ── 경과 타이머 ── */
    _startElapsedTimer() {
        clearInterval(this._timer);
        if (this.status !== 'Active') {
            this._elapsed = this._calcElapsed();
            return;
        }
        this._elapsed = this._calcElapsed();
        this._timer = setInterval(() => {
            this._elapsed = this._calcElapsed();
        }, 60000);
    }

    _calcElapsed() {
        const start = getFieldValue(this._ms, START_FIELD);
        if (!start) return null;
        const end = getFieldValue(this._ms, END_FIELD);
        const diffMs = (end ? new Date(end) : new Date()) - new Date(start);
        const mins = Math.floor(diffMs / 60000);
        if (mins < 60) return `${mins}분`;
        return `${Math.floor(mins / 60)}시간 ${mins % 60}분`;
    }

    disconnectedCallback() {
        clearInterval(this._timer);
    }

    /* ── getters ── */
    get status() {
        return getFieldValue(this._ms, STATUS_FIELD) || '';
    }

    get statusLabel() {
        return STATUS_KO[this.status] || this.status;
    }

    get statusBadgeClass() {
        return this.status === 'Active'
            ? 'banner__badge banner__badge--active'
            : 'banner__badge banner__badge--ended';
    }

    get previewLabel() {
        return getFieldValue(this._ms, PREVIEW_FIELD) || 'OT 고객 서비스 상담';
    }

    get startTimeFormatted() {
        const v = getFieldValue(this._ms, START_FIELD);
        if (!v) return '—';
        return new Date(v).toLocaleString('ko-KR', {
            month: 'numeric', day: 'numeric',
            hour: '2-digit', minute: '2-digit'
        });
    }

    get hasElapsed() {
        return !!this._elapsed;
    }

    get elapsedLabel() {
        return this._elapsed || '';
    }

    get caseId() {
        return getFieldValue(this._ms, CASE_ID_FIELD) || null;
    }

    get caseNumber() {
        return this._caseRecord
            ? getFieldValue(this._caseRecord, 'Case.CaseNumber')
            : this.caseId;
    }

    get caseUrl() {
        if (!this.caseId) return '#';
        return `/lightning/r/Case/${this.caseId}/view`;
    }

    get accountName() {
        if (!this._caseRecord) return null;
        try {
            return this._caseRecord.fields.Account?.value?.fields?.Name?.value || null;
        } catch {
            return null;
        }
    }

    get channelName() {
        return getFieldValue(this._ms, CHANNEL_FIELD) || null;
    }

    get origin() {
        const raw = getFieldValue(this._ms, ORIGIN_FIELD);
        return ORIGIN_KO[raw] || raw || null;
    }
}

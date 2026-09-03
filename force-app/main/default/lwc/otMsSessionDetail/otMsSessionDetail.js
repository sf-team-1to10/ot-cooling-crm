import { LightningElement, api, wire } from 'lwc';
import getSessionInfo from '@salesforce/apex/OtMsInfoPanelController.getSessionInfo';

const STATUS_ACTIVE  = 'Active';
const STATUS_WAITING = 'Waiting';
const STATUS_ENDED   = 'Ended';

export default class OtMsSessionDetail extends LightningElement {
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
    get errorMessage() { return this.error?.body?.message || '세션 정보를 불러오지 못했습니다.'; }

    get statusClass() {
        const s = this.info?.status;
        if (s === STATUS_ACTIVE || s === STATUS_WAITING) return 'ms-badge ms-badge--active';
        if (s === STATUS_ENDED) return 'ms-badge ms-badge--ended';
        return 'ms-badge';
    }

    get startTimeText() { return this._fmt(this.info?.startTime); }
    get endTimeText()   { return this._fmt(this.info?.endTime); }

    get durationText() {
        if (!this.info?.startTime) return '—';
        const end   = this.info.endTime ? new Date(this.info.endTime) : new Date();
        const start = new Date(this.info.startTime);
        const diffMin = Math.round((end - start) / 60000);
        if (diffMin < 60) return diffMin + '분';
        const h = Math.floor(diffMin / 60);
        const m = diffMin % 60;
        return m === 0 ? h + '시간' : h + '시간 ' + m + '분';
    }

    _fmt(raw) {
        if (!raw) return '—';
        return new Date(raw).toLocaleString('ko-KR', {
            month: '2-digit', day: '2-digit',
            hour: '2-digit', minute: '2-digit'
        });
    }
}

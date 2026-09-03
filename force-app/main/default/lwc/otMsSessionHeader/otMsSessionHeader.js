import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHeader from '@salesforce/apex/OtMsSessionHeaderController.getHeader';

const STATUS_ACTIVE  = 'Active';
const STATUS_WAITING = 'Waiting';
const STATUS_ENDED   = 'Ended';

export default class OtMsSessionHeader extends NavigationMixin(LightningElement) {
    @api recordId;

    header;
    error;

    @wire(getHeader, { sessionId: '$recordId' })
    wiredHeader({ data, error }) {
        if (data)  { this.header = data;  this.error  = undefined; }
        if (error) { this.error  = error; this.header = undefined; }
    }

    get isLoading()    { return !this.header && !this.error; }
    get errorMessage() { return this.error?.body?.message || '세션 헤더를 불러오지 못했습니다.'; }

    get sessionTitle() {
        return this.header?.endUserName
            ? this.header.endUserName + ' 와의 대화'
            : 'Guest 와의 대화';
    }

    get customerDisplay() {
        return this.header?.endUserName || 'Guest';
    }

    get statusLabel() {
        const s = this.header?.status;
        if (s === STATUS_ACTIVE)  return '상담 중';
        if (s === STATUS_WAITING) return '대기 중';
        if (s === STATUS_ENDED)   return '종료';
        return s || '—';
    }

    get statusClass() {
        const s = this.header?.status;
        if (s === STATUS_ACTIVE || s === STATUS_WAITING) return 'hl-status hl-status--active';
        if (s === STATUS_ENDED) return 'hl-status hl-status--ended';
        return 'hl-status';
    }

    get startTimeText() { return this._fmt(this.header?.startTime); }
    get endTimeText()   { return this._fmt(this.header?.endTime); }
    get caseUrl()       { return this.header?.caseId ? '/' + this.header.caseId : '#'; }

    _fmt(raw) {
        if (!raw) return '—';
        return new Date(raw).toLocaleString('ko-KR', {
            month: '2-digit', day: '2-digit',
            hour: '2-digit',  minute: '2-digit'
        });
    }

    handleCaseClick(event) {
        event.preventDefault();
        if (!this.header?.caseId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.header.caseId, actionName: 'view' }
        });
    }
}

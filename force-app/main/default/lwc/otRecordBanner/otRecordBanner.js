import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import CASE_STATUS  from '@salesforce/schema/Case.Status';
import CASE_PRIORITY from '@salesforce/schema/Case.Priority';
import WO_STATUS    from '@salesforce/schema/WorkOrder.Status';
import CR_STATUS    from '@salesforce/schema/ChangeRequest.Status';

const OBJECT_FIELDS = {
    Case:          [CASE_STATUS, CASE_PRIORITY],
    WorkOrder:     [WO_STATUS],
    ChangeRequest: [CR_STATUS]
};

const STATUS_CONFIG = {
    // Case
    'Critical': { variant: 'critical', icon: '🚨', msg: '이 케이스는 Critical 우선순위입니다. 즉시 처리가 필요합니다.' },
    'High':     { variant: 'warning',  icon: '⚠️',  msg: '높은 우선순위 케이스입니다. 오늘 내 처리를 권고합니다.' },
    // WorkOrder status
    'Completed':  { variant: 'success', icon: '✅', msg: '워크오더가 완료되었습니다.' },
    'Cancelled':  { variant: 'neutral', icon: 'ℹ️', msg: '취소된 워크오더입니다.' },
    'In Progress':{ variant: 'info',    icon: '🔧', msg: '현재 진행 중인 워크오더입니다.' },
    // CR status
    '요청받음':      { variant: 'info',    icon: '📋', msg: '변경요청이 접수되었습니다. 검토를 시작하세요.' },
    '고객승인대기':    { variant: 'warning', icon: '⏳', msg: '고객 승인을 기다리고 있습니다.' },
    '승인완료':      { variant: 'success', icon: '✅', msg: '고객이 변경을 승인했습니다.' },
    '반려':         { variant: 'critical', icon: '❌', msg: '변경요청이 반려되었습니다. 사유를 확인하세요.' }
};

export default class OtRecordBanner extends LightningElement {
    @api recordId;
    @api objectApiName;

    _status;
    _priority;

    get fields() {
        return OBJECT_FIELDS[this.objectApiName] || [];
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$fields' })
    wiredRecord({ data }) {
        if (!data) return;
        if (this.objectApiName === 'Case') {
            this._status   = getFieldValue(data, CASE_STATUS);
            this._priority = getFieldValue(data, CASE_PRIORITY);
        } else if (this.objectApiName === 'WorkOrder') {
            this._status = getFieldValue(data, WO_STATUS);
        } else if (this.objectApiName === 'ChangeRequest') {
            this._status = getFieldValue(data, CR_STATUS);
        }
    }

    get _key() {
        if (this.objectApiName === 'Case') return this._priority;
        return this._status;
    }

    get _cfg() {
        return STATUS_CONFIG[this._key] || null;
    }

    get showBanner()    { return !!this._cfg; }
    get icon()          { return this._cfg?.icon || ''; }
    get message()       { return this._cfg?.msg  || ''; }
    get badgeVariant()  { return this._cfg?.variant || 'neutral'; }
    get statusLabel()   { return this._key || ''; }
    get ariaLabel()     { return `${this.statusLabel}: ${this.message}`; }

    get bannerClass() {
        const v = this._cfg?.variant || 'neutral';
        return `ot-banner ot-banner--${v}`;
    }
}

import { LightningElement, api } from 'lwc';

export default class T5RepairResultCard extends LightningElement {
    // Flow inputs (Flow → component). Defaults reproduce the mockup for standalone demo.
    @api workOrderNumber = 'WO 00000318';
    @api measurePoint = 'F-07';
    @api initialTorque = 71;
    @api retorqueTorque = 111;
    @api flowBefore = 1961;
    @api flowAfter = 2080;
    @api isPending = false;
    @api recurrenceNote = '68 → 112, 71 → 111로 반복됐습니다. 최초 실패값은 덮어쓰지 않고 둘 다 보존합니다.';
    @api recurrenceTitle = '2022년과 같은 자리, 같은 문제';

    get tiles() {
        return [
            { key: 'initial', label: '최초 체결 N·m', value: this.initialTorque, tone: 'fail' },
            { key: 'retorque', label: '재조임 후 N·m', value: this.retorqueTorque, tone: 'pass' },
            { key: 'before', label: '조치 전 L/min', value: this.formatNumber(this.flowBefore), tone: 'warn' },
            { key: 'after', label: '조치 후 L/min', value: this.formatNumber(this.flowAfter), tone: 'pass' }
        ].map(t => ({ ...t, tileClass: `tile tile_${t.tone}`, valueClass: `tile__value tile__value_${t.tone}` }));
    }

    get statusLabel() {
        return this.isPending ? '진행 중' : '확정';
    }

    get statusClass() {
        return this.isPending ? 'status status_pending' : 'status status_confirmed';
    }

    formatNumber(value) {
        if (value === null || value === undefined || value === '') {
            return '—';
        }
        const num = Number(value);
        return Number.isNaN(num) ? value : num.toLocaleString('en-US');
    }
}
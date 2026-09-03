import { LightningElement, api } from 'lwc';

/**
 * 공용 KPI 스트립.
 * items 형태:
 *   Array<{
 *     label: string,
 *     value: string|number,
 *     trend?: 'up'|'down'|'flat',
 *     tone?: 'brand'|'success'|'warning'|'danger'|'muted'
 *   }>
 */
export default class OtKpiStrip extends LightningElement {
    @api items = [];

    get normalized() {
        return (this.items || []).map((it, i) => ({
            key: i,
            label: it.label,
            value: (it.value === null || it.value === undefined) ? '—' : it.value,
            toneClass: `kpi-value kpi-tone-${it.tone || 'brand'}`,
            trendIcon:
                it.trend === 'up' ? 'utility:arrowup' :
                it.trend === 'down' ? 'utility:arrowdown' :
                it.trend === 'flat' ? 'utility:dash' : null,
            trendClass: `kpi-trend kpi-trend-${it.trend || 'none'}`
        }));
    }
}

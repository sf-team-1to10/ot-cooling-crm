import { LightningElement, wire } from 'lwc';
import getQuarterlyPerformance from '@salesforce/apex/OtSalesDashboardController.getQuarterlyPerformance';

const KRW = new Intl.NumberFormat('ko-KR', { style: 'currency', currency: 'KRW', maximumFractionDigits: 0 });

export default class OtSalesQuarterly extends LightningElement {
    closed = 0;
    openHighProb = 0;
    goal = 600000000;
    achievementPct = 0;
    progressPct = 0;
    daysRemaining = 0;
    _monthlyData = [];

    @wire(getQuarterlyPerformance)
    wiredData({ data }) {
        if (data) {
            this.closed = data.closed || 0;
            this.openHighProb = data.openHighProb || 0;
            this.goal = data.goal || 600000000;
            this.achievementPct = data.achievementPct || 0;
            this.progressPct = data.progressPct || 0;
            this.daysRemaining = data.daysRemaining || 0;
            this._monthlyData = data.monthlyData || [];
        }
    }

    get closedFormatted() { return KRW.format(this.closed); }
    get openHighProbFormatted() { return KRW.format(this.openHighProb); }
    get goalFormatted() { return KRW.format(this.goal); }

    get donutDash() {
        const circumference = 2 * Math.PI * 50;
        const filled = (this.achievementPct / 100) * circumference;
        return `${filled} ${circumference}`;
    }

    get monthBars() {
        const maxVal = 300000000; // 300M as chart max
        const chartH = 200; // px height of chart area
        return this._monthlyData.map((m, i) => ({
            key: `m${i}`,
            label: m.label,
            actualStyle: `height: ${Math.round((m.actual / maxVal) * chartH)}px`,
            projectedStyle: `height: ${Math.round((m.projected / maxVal) * chartH)}px`,
            actualTooltip: KRW.format(m.actual),
            projectedTooltip: KRW.format(m.projected)
        }));
    }
}
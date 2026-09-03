import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Name';
import getDashboardData from '@salesforce/apex/OtSalesDashboardController.getDashboardData';

const KRW = new Intl.NumberFormat('ko-KR', {
    style: 'currency', currency: 'KRW', maximumFractionDigits: 0
});

export default class OtSalesDashboard extends NavigationMixin(LightningElement) {
    userName;
    closed = 0;
    openHighProb = 0;
    goal = 0;
    quarterLabel = '';
    pipelineStages = [];
    keyDeals = [];
    contracts = [];
    isLoading = true;

    @wire(getRecord, { recordId: USER_ID, fields: [NAME_FIELD] })
    wiredUser({ data }) {
        if (data) this.userName = getFieldValue(data, NAME_FIELD);
    }

    @wire(getDashboardData)
    wiredDashboard({ data, error }) {
        if (data) {
            this.closed = data.closed || 0;
            this.openHighProb = data.openHighProb || 0;
            this.goal = data.goal || 0;
            this.quarterLabel = data.quarterLabel || '';

            const pipeline = data.pipeline || {};
            const maxVal = Math.max(...Object.values(pipeline), 1);
            const stageOrder = ['Qualification', 'Proposal', 'Negotiation', 'Closed Won'];
            const stageColors = {
                'Qualification': '#b0bec5',
                'Proposal': '#90a4ae',
                'Negotiation': '#546e7a',
                'Closed Won': '#37474f'
            };
            this.pipelineStages = stageOrder
                .filter(s => pipeline[s] != null)
                .map(s => {
                    const w = Math.max(Math.round((pipeline[s] / maxVal) * 100), 4);
                    const c = stageColors[s] || '#78909c';
                    return {
                        stage: s,
                        amount: pipeline[s],
                        amountFormatted: KRW.format(pipeline[s]),
                        width: w,
                        color: c,
                        barStyle: `width:${w}%;background:${c}`
                    };
                });

            this.keyDeals = (data.keyDeals || []).map(d => ({
                ...d,
                amountFormatted: d.amount != null ? KRW.format(d.amount) : '—',
                closeDateFormatted: this._fmtDate(d.closeDate)
            }));

            this.contracts = (data.contracts || []).map(c => ({
                ...c,
                endDateFormatted: this._fmtDate(c.endDate)
            }));

            this.isLoading = false;
        } else if (error) {
            this.isLoading = false;
        }
    }

    get greeting() {
        const now = new Date();
        const days = ['일', '월', '화', '수', '목', '금', '토'];
        const y = now.getFullYear();
        const m = now.getMonth() + 1;
        const d = now.getDate();
        const dayName = days[now.getDay()];
        const name = this.userName || '';
        const hour = now.getHours();
        let timeGreeting = 'Good morning';
        if (hour >= 12 && hour < 18) timeGreeting = 'Good afternoon';
        else if (hour >= 18) timeGreeting = 'Good evening';
        return `${timeGreeting}, ${name}. — ${y}년 ${m}월 ${d}일 (${dayName})`;
    }

    get closedFormatted() { return KRW.format(this.closed); }
    get openHighProbFormatted() { return KRW.format(this.openHighProb); }
    get goalFormatted() { return KRW.format(this.goal); }

    get achievementRate() {
        if (!this.goal) return '0%';
        return Math.round((this.closed / this.goal) * 100) + '%';
    }

    get achievementRateClass() {
        if (!this.goal) return 'slds-text-heading_small rate-red';
        const pct = Math.round((this.closed / this.goal) * 100);
        if (pct >= 80) return 'rate-green';
        if (pct >= 50) return 'rate-blue';
        return 'rate-red';
    }

    get progressStyle() {
        if (!this.goal) return 'width:0%';
        const pct = Math.min(Math.round((this.closed / this.goal) * 100), 100);
        return `width:${pct}%`;
    }

    get quotaBars() {
        const months = [];
        const now = new Date();
        const qStartMonth = Math.floor(now.getMonth() / 3) * 3;
        for (let i = 0; i < 3; i++) {
            const m = qStartMonth + i + 1;
            months.push({ key: `m${i}`, label: `${m}월` });
        }
        return months;
    }

    get quarterAnnotation() {
        return `이번 분기 누적 · 실적(진회색) / 예상연회(채)`;
    }

    get hasKeyDeals() { return this.keyDeals.length > 0; }
    get hasContracts() { return this.contracts.length > 0; }
    get hasPipeline() { return this.pipelineStages.length > 0; }

    handleNavigate(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    _fmtDate(isoStr) {
        if (!isoStr) return '—';
        const parts = isoStr.split('-');
        return `${parts[1]}/${parts[2]}`;
    }
}
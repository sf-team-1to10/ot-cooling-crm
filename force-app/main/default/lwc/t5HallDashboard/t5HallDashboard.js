import { LightningElement, wire } from 'lwc';
import getHallSummary from '@salesforce/apex/T5HallDashboardController.getHallSummary';

const TREND_META = {
    정상: { badge: 'slds-badge slds-theme_success', order: 3 },
    주의: { badge: 'slds-badge slds-theme_warning', order: 2 },
    이상: { badge: 'slds-badge slds-theme_error', order: 1 },
    미점검: { badge: 'slds-badge', order: 4 }
};

export default class T5HallDashboard extends LightningElement {
    data;
    error;

    @wire(getHallSummary)
    wiredSummary({ data, error }) {
        if (data) {
            this.data = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.data = undefined;
        }
    }

    get isLoading() {
        return !this.data && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || 'Hall 대시보드 데이터를 불러오지 못했습니다.';
    }

    get hasAssets() {
        return this.data && this.data.totalAssets > 0;
    }

    get tiles() {
        if (!this.data) {
            return [];
        }
        return [
            { key: 'critical', label: '이상', count: this.data.criticalCount, cls: 'tile tile--critical' },
            { key: 'warning', label: '주의', count: this.data.warningCount, cls: 'tile tile--warning' },
            { key: 'normal', label: '정상', count: this.data.normalCount, cls: 'tile tile--normal' },
            { key: 'uninspected', label: '미점검', count: this.data.uninspectedCount, cls: 'tile tile--neutral' }
        ];
    }

    get assetRows() {
        if (!this.data) {
            return [];
        }
        // 이상 → 주의 → 정상 → 미점검 순으로 정렬해 심각한 것이 위로
        return [...this.data.assets]
            .map((a) => ({
                ...a,
                badgeClass: (TREND_META[a.trend] || TREND_META['미점검']).badge,
                sortOrder: (TREND_META[a.trend] || TREND_META['미점검']).order
            }))
            .sort((x, y) => x.sortOrder - y.sortOrder);
    }

    get preventiveLabel() {
        if (!this.data) {
            return '';
        }
        return `${this.data.preventiveDone} / ${this.data.preventiveTotal} 완료`;
    }

    get preventiveProgress() {
        return this.data ? this.data.preventiveProgress : 0;
    }

    get progressStyle() {
        return `width: ${this.preventiveProgress}%;`;
    }
}
import { LightningElement, api, wire } from 'lwc';
import getBriefing from '@salesforce/apex/T5DispatchBriefingController.getBriefing';

export default class OtDispatchBriefingWorkbench extends LightningElement {
    @api recordId;

    briefing;
    error;

    @wire(getBriefing, { caseId: '$recordId' })
    wiredBriefing({ data, error }) {
        if (data) {
            this.briefing = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.briefing = undefined;
        }
    }

    get isLoading() {
        return !this.briefing && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || '브리핑 데이터를 불러오지 못했습니다.';
    }

    get priority() {
        return this.briefing?.priority;
    }

    get rationale() {
        return this.briefing?.priorityRationale;
    }

    get maxDriftText() {
        const r = this.rationale;
        if (!r || r.maxDriftValue == null) {
            return '';
        }
        return `${r.maxDriftValue}% · ${r.comparedCount}대 중 최대`;
    }

    // 12대 비교 행 — 대표값을 표시용으로 가공(A-07 강조 플래그 포함)
    get comparisonRows() {
        const rows = this.briefing?.comparisons || [];
        const targetName = this.briefing?.targetAssetName;
        return rows.map((c) => {
            const isTarget = c.assetName === targetName;
            return {
                ...c,
                key: c.assetId,
                isTarget,
                driftText: c.driftFromBaseline == null ? '—' : `${c.driftFromBaseline}%`,
                measuredText: c.measuredValue == null ? '—' : `${c.measuredValue} L/min`,
                revisionText: c.appliedRevision || '—',
                rowClass: isTarget
                    ? 'slds-hint-parent target-row'
                    : 'slds-hint-parent',
                trendClass: this.trendBadgeClass(c.trendFlag),
                pastFailureText: c.hasPastFailure ? '있음' : '—'
            };
        });
    }

    trendBadgeClass(trend) {
        if (trend === '이상') {
            return 'slds-badge slds-theme_error';
        }
        if (trend === '주의') {
            return 'slds-badge slds-theme_warning';
        }
        return 'slds-badge';
    }

    get hasComparisons() {
        return (this.briefing?.comparisons || []).length > 0;
    }

    get similarCasesSummary() {
        return this.briefing?.similarCasesSummary;
    }

    get briefingBody() {
        return this.briefing?.briefingBody;
    }

    get hasPastFailure() {
        return this.rationale?.hasPastFailure === true;
    }
}

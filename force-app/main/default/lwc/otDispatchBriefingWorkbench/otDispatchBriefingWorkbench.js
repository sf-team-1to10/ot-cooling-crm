import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getBriefing from '@salesforce/apex/T5DispatchBriefingController.getBriefing';

export default class OtDispatchBriefingWorkbench extends LightningElement {
    // Record page에서는 자동 주입, App Page에서는 pageReference state에서 해석한다.
    @api recordId;
    _stateRecordId;

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        const stateId = pageRef?.state?.c__recordId || pageRef?.attributes?.recordId;
        if (stateId) {
            this._stateRecordId = stateId;
        }
    }

    get effectiveRecordId() {
        // undefined를 반환해야 wire가 실행되지 않는다(null이면 Apex가 예외를 던짐).
        return this.recordId || this._stateRecordId || undefined;
    }

    briefing;
    error;

    @wire(getBriefing, { caseId: '$effectiveRecordId' })
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
        return this.toSections(this.briefing?.similarCasesSummary);
    }

    get briefingBody() {
        return this.toSections(this.briefing?.briefingBody);
    }

    // '■' 섹션 마커 단위로 문단을 나눠 가독성 확보
    toSections(raw) {
        if (!raw) {
            return raw;
        }
        return raw
            .split('■')
            .map((seg) => seg.trim())
            .filter((seg) => seg.length > 0)
            .map((seg) => `<p class="briefing-section">■ ${seg}</p>`)
            .join('');
    }

    get hasPastFailure() {
        return this.rationale?.hasPastFailure === true;
    }
}

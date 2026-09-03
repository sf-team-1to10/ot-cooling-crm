import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import { EnclosingTabId, IsConsoleNavigation, openSubtab } from 'lightning/platformWorkspaceApi';

import CASE_ID_FIELD from '@salesforce/schema/MessagingSession.CaseId';

const CASE_FIELDS = [
    'Case.CaseNumber', 'Case.Subject', 'Case.Status', 'Case.Priority',
    'Case.Type', 'Case.Origin', 'Case.Description',
    'Case.AssetId',
    'Case.Account.Name', 'Case.Asset.Name',
    'Case.Contact.Name', 'Case.Owner.Name'
];

const ASSET_FIELDS = [
    'Asset.Name',
    'Asset.Status',
    'Asset.Latest_Gauges_JSON__c',
    'Asset.Latest_Trend_Flag__c',
    'Asset.Site_Location__c'
];

const CASE_STATUS_KO = {
    New: '신규', 'In Progress': '처리 중', Escalated: '에스컬레이션',
    'On Hold': '보류', Closed: '완료', Resolved: '해결됨'
};
const CASE_PRIORITY_KO = { High: '높음', Medium: '보통', Low: '낮음' };
const ORIGIN_KO = { InboundInitiated: '인바운드', OutboundInitiated: '아웃바운드', Agent: '에이전트' };

export default class OtMsSidebarCenter extends NavigationMixin(LightningElement) {
    @api recordId;
    _ms = null;
    _case = null;
    _asset = null;

    @wire(IsConsoleNavigation) isConsole;
    @wire(EnclosingTabId) enclosingTabId;

    @wire(getRecord, { recordId: '$recordId', fields: [CASE_ID_FIELD] })
    wiredMs({ data }) { this._ms = data || null; }

    @wire(getRecord, { recordId: '$caseId', fields: CASE_FIELDS })
    wiredCase({ data }) { this._case = data || null; }

    @wire(getRecord, { recordId: '$assetId', fields: ASSET_FIELDS })
    wiredAsset({ data }) { this._asset = data || null; }

    /* ── Case ── */
    get caseId() { return getFieldValue(this._ms, CASE_ID_FIELD) || null; }
    get hasCaseId() { return !!this.caseId; }
    get isLoadingCase() { return this.hasCaseId && !this._case; }

    get caseNumber()  { return this._cf('CaseNumber')  || '—'; }
    get caseSubject() { return this._cf('Subject')     || '—'; }
    get caseType()    { return this._cf('Type')        || '—'; }
    get caseDesc()    { return this._cf('Description') || ''; }
    get hasDesc()     { return !!this.caseDesc; }

    get caseOrigin() {
        const raw = this._cf('Origin');
        return ORIGIN_KO[raw] || raw || '—';
    }
    get caseStatus() {
        const raw = this._cf('Status');
        return CASE_STATUS_KO[raw] || raw || '—';
    }
    get casePriority() {
        const raw = this._cf('Priority');
        return CASE_PRIORITY_KO[raw] || raw || '—';
    }
    get casePriorityClass() {
        const raw = this._cf('Priority');
        if (raw === 'High')   return 'badge badge--neg';
        if (raw === 'Medium') return 'badge badge--warn';
        return 'badge badge--neutral';
    }

    get caseAccountName() { return this._cRel('Account') || '—'; }
    get caseAssetName()   { return this._cRel('Asset')   || '—'; }
    get caseContactName() { return this._cRel('Contact') || '—'; }
    get caseOwnerName()   { return this._cRel('Owner')   || '—'; }
    get caseUrl() { return this.caseId ? `/lightning/r/Case/${this.caseId}/view` : '#'; }

    _cf(name) { return this._case?.fields[name]?.value ?? null; }
    _cRel(name) { return this._case?.fields[name]?.value?.fields?.Name?.value ?? null; }

    handleCaseClick(event) {
        event.preventDefault();
        this._openAsSubtab(this.caseId, 'Case');
    }

    handleAssetClick(event) {
        event.preventDefault();
        this._openAsSubtab(this.assetId, 'Asset');
    }

    async _openAsSubtab(recordId, objectApiName) {
        if (!recordId) return;
        if (this.isConsole && this.enclosingTabId) {
            try {
                await openSubtab(this.enclosingTabId, {
                    recordId,
                    focus: true
                });
                return;
            } catch (e) {
                // fall through to standard nav
            }
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName, actionName: 'view' }
        });
    }

    handleNewCase() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Case', actionName: 'new' }
        });
    }

    /* ── Asset ── */
    get assetId() { return this._cf('AssetId') || null; }
    get hasAssetId() { return !!this.assetId; }
    get isLoadingAsset() { return this.hasAssetId && !this._asset; }
    get assetUrl() { return this.assetId ? `/lightning/r/Asset/${this.assetId}/view` : '#'; }

    get assetName()   { return this._af('Name')            || '—'; }
    get assetStatus() { return this._af('Status')          || '—'; }
    get assetSite()   { return this._af('Site_Location__c') || '—'; }
    get assetTrendFlag() { return this._af('Latest_Trend_Flag__c') || ''; }

    get assetTrendClass() {
        const t = this.assetTrendFlag;
        if (t === '주의' || t === 'Warning') return 'badge badge--warn';
        if (t === '심각' || t === '경보' || t === 'Critical') return 'badge badge--neg';
        return 'badge badge--neutral';
    }

    _af(name) { return this._asset?.fields[name]?.value ?? null; }

    get gauges() {
        const raw = this._af('Latest_Gauges_JSON__c');
        if (!raw) return [];
        try {
            const arr = JSON.parse(raw);
            if (!Array.isArray(arr)) return [];
            return arr.map((g, i) => this._buildGauge(g, i));
        } catch (e) {
            return [];
        }
    }

    get hasGauges() { return this.gauges.length > 0; }

    _buildGauge(g, i) {
        const cur = Number(g.currentValue);
        const prev = Number(g.previousValue);
        const base = Number(g.baselineValue);
        const delta = Number.isFinite(cur) && Number.isFinite(prev) ? cur - prev : null;
        const pctFromBase = Number.isFinite(cur) && Number.isFinite(base) && base !== 0
            ? ((cur - base) / base) * 100
            : null;

        let deltaClass = 'delta';
        let deltaText = '—';
        if (delta !== null) {
            if (delta > 0) { deltaClass = 'delta delta--up'; deltaText = `▲ ${this._fmt(Math.abs(delta))}`; }
            else if (delta < 0) { deltaClass = 'delta delta--down'; deltaText = `▼ ${this._fmt(Math.abs(delta))}`; }
            else { deltaText = '― 변동 없음'; }
        }

        const pctText = pctFromBase !== null
            ? `${pctFromBase >= 0 ? '+' : ''}${pctFromBase.toFixed(1)}%`
            : '';

        const trend = g.trendFlag || '';
        let trendClass = 'chip chip--neutral';
        if (trend === '주의' || trend === 'Warning') trendClass = 'chip chip--warn';
        if (trend === '심각' || trend === '경보' || trend === 'Critical') trendClass = 'chip chip--neg';

        // sparkline
        const values = Array.isArray(g.sparklineValues) ? g.sparklineValues.map(Number).filter(Number.isFinite) : [];
        const spark = this._sparkPath(values);

        return {
            key: `${g.measurementItemCode || 'gauge'}-${i}`,
            label: g.measurementItemCode || '측정값',
            currentText: this._fmt(cur),
            deltaText,
            deltaClass,
            baselineText: Number.isFinite(base) ? this._fmt(base) : '—',
            pctText,
            trend,
            trendClass,
            hasTrend: !!trend,
            hasSpark: spark.hasSpark,
            sparkPath: spark.path,
            sparkArea: spark.area,
            viewBox: spark.viewBox
        };
    }

    _sparkPath(values) {
        if (!values.length) return { hasSpark: false, path: '', area: '', viewBox: '0 0 100 30' };
        const W = 100, H = 30, PAD = 2;
        const min = Math.min(...values);
        const max = Math.max(...values);
        const range = max - min || 1;
        const n = values.length;
        const step = n > 1 ? (W - PAD * 2) / (n - 1) : 0;
        const pts = values.map((v, i) => {
            const x = PAD + step * i;
            const y = PAD + (1 - (v - min) / range) * (H - PAD * 2);
            return [x, y];
        });
        const path = pts.map((p, i) => (i === 0 ? `M ${p[0].toFixed(1)} ${p[1].toFixed(1)}` : `L ${p[0].toFixed(1)} ${p[1].toFixed(1)}`)).join(' ');
        const area = `${path} L ${pts[pts.length - 1][0].toFixed(1)} ${(H - PAD).toFixed(1)} L ${pts[0][0].toFixed(1)} ${(H - PAD).toFixed(1)} Z`;
        return { hasSpark: true, path, area, viewBox: `0 0 ${W} ${H}` };
    }

    _fmt(n) {
        if (!Number.isFinite(n)) return '—';
        return n.toLocaleString('ko-KR', { maximumFractionDigits: 2 });
    }
}

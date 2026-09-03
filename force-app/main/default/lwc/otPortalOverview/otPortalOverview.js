import { LightningElement, wire } from 'lwc';
import getOverviewSummary from '@salesforce/apex/OtPortalOverviewController.getOverviewSummary';
import getRecentAlerts    from '@salesforce/apex/OtPortalOverviewController.getRecentAlerts';
import getMyAssets        from '@salesforce/apex/OTMyAssetsController.getMyAssets';

const CIRCUMFERENCE = 2 * Math.PI * 54; // r=54

const PRIORITY_VARIANT = { P1: 'critical', P2: 'warning', P3: 'info', P4: 'neutral' };

export default class OtPortalOverview extends LightningElement {
    summary = { totalAssets: 0, attentionAssets: 0, unacknowledgedAlerts: 0, openCases: 0 };
    alerts  = [];
    _assets = [];

    _summaryLoaded = false;
    _alertsLoaded  = false;
    _assetsLoaded  = false;

    // ── wire handlers ─────────────────────────────────────────────────────────

    @wire(getOverviewSummary)
    wiredSummary({ data, error }) {
        if (data) {
            this.summary        = data;
            this._summaryLoaded = true;
        } else if (error) {
            this._summaryLoaded = true;
        }
    }

    @wire(getRecentAlerts, { limitCount: 5 })
    wiredAlerts({ data, error }) {
        if (data) {
            this.alerts        = data.map(a => this._enrichAlert(a));
            this._alertsLoaded = true;
        } else if (error) {
            this._alertsLoaded = true;
        }
    }

    @wire(getMyAssets)
    wiredAssets({ data, error }) {
        if (data) {
            this._assets       = data;
            this._assetsLoaded = true;
        } else if (error) {
            this._assetsLoaded = true;
        }
    }

    // ── loading state ─────────────────────────────────────────────────────────

    get isLoading() {
        return !(this._summaryLoaded && this._alertsLoaded && this._assetsLoaded);
    }

    // ── alert helpers ─────────────────────────────────────────────────────────

    get hasAlerts() { return this.alerts.length > 0; }

    _enrichAlert(raw) {
        const d = raw.startedAt ? new Date(raw.startedAt) : null;
        return {
            ...raw,
            startedAtFormatted: d
                ? `${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`
                : '—',
            priorityVariant: PRIORITY_VARIANT[raw.priority] || 'neutral'
        };
    }

    // ── donut chart ───────────────────────────────────────────────────────────

    get totalAssetCount() { return this._assets.length; }

    get normalCount() {
        return this._assets.filter(a => a.trendFlag === '정상').length;
    }
    get warningCount() {
        return this._assets.filter(a => a.trendFlag === '주의').length;
    }
    get criticalCount() {
        return this._assets.filter(a => a.trendFlag === '이상').length;
    }
    get unknownCount() {
        return this._assets.filter(
            a => !a.trendFlag || !['정상','주의','이상'].includes(a.trendFlag)
        ).length;
    }

    _segDash(count) {
        const total = this.totalAssetCount;
        if (total === 0) return `0 ${CIRCUMFERENCE}`;
        const arc = (count / total) * CIRCUMFERENCE;
        return `${arc.toFixed(2)} ${CIRCUMFERENCE}`;
    }

    _segOffset(priorCount) {
        const total = this.totalAssetCount;
        if (total === 0) return 0;
        // SVG circles start at 3 o'clock; rotate to 12 o'clock = -CIRCUMFERENCE/4
        const priorArc = (priorCount / total) * CIRCUMFERENCE;
        return -(CIRCUMFERENCE / 4) - priorArc;
    }

    get normalDash()     { return this._segDash(this.normalCount); }
    get warningDash()    { return this._segDash(this.warningCount); }
    get criticalDash()   { return this._segDash(this.criticalCount); }

    get warningOffset()  { return this._segOffset(this.normalCount).toFixed(2); }
    get criticalOffset() {
        return this._segOffset(this.normalCount + this.warningCount).toFixed(2);
    }

    // ── navigation events ─────────────────────────────────────────────────────

    handleGoAssets() {
        this.dispatchEvent(new CustomEvent('navigate', { detail: 'assets' }));
    }

    handleGoAlerts() {
        // 현재는 자산 화면으로 이동 (별도 알림 페이지 미구현)
        this.dispatchEvent(new CustomEvent('navigate', { detail: 'assets' }));
    }
}

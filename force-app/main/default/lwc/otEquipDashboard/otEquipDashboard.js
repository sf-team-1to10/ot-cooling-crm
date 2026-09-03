import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getEquipmentDashboard from '@salesforce/apex/OTEquipDashboardController.getEquipmentDashboard';
import getEquipmentDetail from '@salesforce/apex/OTEquipDashboardController.getEquipmentDetail';
import getLocationInfo from '@salesforce/apex/OTEquipDashboardController.getLocationInfo';
import getAlerts from '@salesforce/apex/OTEquipDashboardController.getAlerts';
import CDU_IMG from '@salesforce/resourceUrl/OT_Product_CDU';
import CDU_A07_IMG from '@salesforce/resourceUrl/OT_CDU_Gallery_01';
import CX_IMG from '@salesforce/resourceUrl/OT_Product_CX';
import CRAH_IMG from '@salesforce/resourceUrl/OT_Product_CRAH';
import COOLBIT_ALERT from '@salesforce/resourceUrl/OT_Coolbit_Alert';
import COOLBIT_CLEAR from '@salesforce/resourceUrl/OT_Coolbit_Clear';

const PAGE_SIZE = 10;

// 상태 정렬 우선순위: critical(0) > warning(1) > ok(2)
const STATE_RANK = { critical: 0, warning: 1, ok: 2 };

// CDU-A-07 이외 장비별 정상 범위 폴백 데이터 (이름 → gaugesJson)
const FALLBACK_MAP = {
    // ── CDU-A 계열 (유량 120~160 L/min, 공급온도 12~17°C) ──
    'CDU-A-01': [{measurementItemCode:'FLOW',label:'냉각수 유량',unit:'L/min',currentValue:138,previousValue:136,threshold:120,sparklineValues:[135,136,137,138,137,138,138,139,138,138]},{measurementItemCode:'TEMP_SUP',label:'공급 온도',unit:'°C',currentValue:13.8,previousValue:13.6,threshold:18,sparklineValues:[13.5,13.6,13.7,13.8,13.7,13.8,13.9,13.8,13.8,13.8]}],
    'CDU-A-02': [{measurementItemCode:'FLOW',label:'냉각수 유량',unit:'L/min',currentValue:151,previousValue:148,threshold:120,sparklineValues:[145,146,148,149,150,150,151,151,151,151]},{measurementItemCode:'TEMP_SUP',label:'공급 온도',unit:'°C',currentValue:14.5,previousValue:14.2,threshold:18,sparklineValues:[14.0,14.1,14.2,14.3,14.3,14.4,14.5,14.5,14.5,14.5]}],
    'CDU-A-03': [{measurementItemCode:'FLOW',label:'냉각수 유량',unit:'L/min',currentValue:144,previousValue:143,threshold:120,sparklineValues:[142,145,143,146,143,144,145,143,144,144]},{measurementItemCode:'TEMP_SUP',label:'공급 온도',unit:'°C',currentValue:13.2,previousValue:13.3,threshold:18,sparklineValues:[13.1,13.4,13.2,13.5,13.2,13.3,13.4,13.2,13.3,13.2]}],
    'CDU-A-04': [{measurementItemCode:'FLOW',label:'냉각수 유량',unit:'L/min',currentValue:156,previousValue:155,threshold:120,sparklineValues:[153,154,155,155,156,156,157,156,156,156]},{measurementItemCode:'TEMP_SUP',label:'공급 온도',unit:'°C',currentValue:15.1,previousValue:15.0,threshold:18,sparklineValues:[14.8,14.9,15.0,15.1,15.1,15.2,15.1,15.1,15.1,15.1]}],
    'CDU-A-05': [{measurementItemCode:'FLOW',label:'냉각수 유량',unit:'L/min',currentValue:133,previousValue:136,threshold:120,sparklineValues:[139,138,137,136,135,135,134,134,133,133]},{measurementItemCode:'TEMP_SUP',label:'공급 온도',unit:'°C',currentValue:13.6,previousValue:13.8,threshold:18,sparklineValues:[14.0,13.9,13.8,13.8,13.7,13.7,13.6,13.6,13.6,13.6]}],
    'CDU-A-06': [{measurementItemCode:'FLOW',label:'냉각수 유량',unit:'L/min',currentValue:148,previousValue:147,threshold:120,sparklineValues:[146,147,147,148,148,149,148,148,148,148]},{measurementItemCode:'TEMP_SUP',label:'공급 온도',unit:'°C',currentValue:14.9,previousValue:14.8,threshold:18,sparklineValues:[14.6,14.7,14.8,14.8,14.9,14.9,15.0,14.9,14.9,14.9]}],
    'CDU-A-08': [{measurementItemCode:'FLOW',label:'냉각수 유량',unit:'L/min',currentValue:141,previousValue:142,threshold:120,sparklineValues:[143,140,142,141,143,140,142,141,141,141]},{measurementItemCode:'TEMP_SUP',label:'공급 온도',unit:'°C',currentValue:14.1,previousValue:14.2,threshold:18,sparklineValues:[14.3,14.0,14.2,14.1,14.3,14.0,14.2,14.1,14.1,14.1]}],
    'CDU-A-09': [{measurementItemCode:'FLOW',label:'냉각수 유량',unit:'L/min',currentValue:158,previousValue:157,threshold:120,sparklineValues:[155,156,156,157,157,158,158,159,158,158]},{measurementItemCode:'TEMP_SUP',label:'공급 온도',unit:'°C',currentValue:15.4,previousValue:15.3,threshold:18,sparklineValues:[15.1,15.2,15.2,15.3,15.3,15.4,15.4,15.5,15.4,15.4]}],
    'CDU-A-10': [{measurementItemCode:'FLOW',label:'냉각수 유량',unit:'L/min',currentValue:135,previousValue:135,threshold:120,sparklineValues:[134,135,134,136,135,135,136,135,135,135]},{measurementItemCode:'TEMP_SUP',label:'공급 온도',unit:'°C',currentValue:13.4,previousValue:13.4,threshold:18,sparklineValues:[13.3,13.4,13.3,13.5,13.4,13.4,13.5,13.4,13.4,13.4]}],
    'CDU-A-11': [{measurementItemCode:'FLOW',label:'냉각수 유량',unit:'L/min',currentValue:147,previousValue:144,threshold:120,sparklineValues:[143,143,144,144,145,145,146,146,147,147]},{measurementItemCode:'TEMP_SUP',label:'공급 온도',unit:'°C',currentValue:14.7,previousValue:14.5,threshold:18,sparklineValues:[14.4,14.4,14.5,14.5,14.6,14.6,14.7,14.7,14.7,14.7]}],
    'CDU-A-12': [{measurementItemCode:'FLOW',label:'냉각수 유량',unit:'L/min',currentValue:153,previousValue:152,threshold:120,sparklineValues:[151,151,152,152,153,153,153,154,153,153]},{measurementItemCode:'TEMP_SUP',label:'공급 온도',unit:'°C',currentValue:15.0,previousValue:14.9,threshold:18,sparklineValues:[14.8,14.8,14.9,14.9,15.0,15.0,15.0,15.1,15.0,15.0]}],
    // ── CX 계열 (COP 3.2~4.5, 환수온도 16~21°C) ──
    'CX-01': [{measurementItemCode:'EFF',label:'냉각 효율 (COP)',unit:'',currentValue:3.8,previousValue:3.7,threshold:3.0,sparklineValues:[3.6,3.6,3.7,3.7,3.8,3.8,3.9,3.8,3.8,3.8]},{measurementItemCode:'TEMP_RET',label:'환수 온도',unit:'°C',currentValue:17.8,previousValue:17.6,threshold:22,sparklineValues:[17.4,17.5,17.6,17.7,17.7,17.8,17.9,17.8,17.8,17.8]}],
    'CX-02': [{measurementItemCode:'EFF',label:'냉각 효율 (COP)',unit:'',currentValue:4.3,previousValue:4.2,threshold:3.0,sparklineValues:[4.0,4.1,4.1,4.2,4.2,4.3,4.3,4.4,4.3,4.3]},{measurementItemCode:'TEMP_RET',label:'환수 온도',unit:'°C',currentValue:19.2,previousValue:19.0,threshold:22,sparklineValues:[18.8,18.9,19.0,19.0,19.1,19.1,19.2,19.2,19.2,19.2]}],
    'CX-03': [{measurementItemCode:'EFF',label:'냉각 효율 (COP)',unit:'',currentValue:3.5,previousValue:3.6,threshold:3.0,sparklineValues:[3.8,3.7,3.7,3.6,3.6,3.5,3.5,3.5,3.5,3.5]},{measurementItemCode:'TEMP_RET',label:'환수 온도',unit:'°C',currentValue:16.4,previousValue:16.6,threshold:22,sparklineValues:[17.0,16.9,16.8,16.7,16.6,16.5,16.4,16.4,16.4,16.4]}],
    'CX-04': [{measurementItemCode:'EFF',label:'냉각 효율 (COP)',unit:'',currentValue:4.1,previousValue:4.0,threshold:3.0,sparklineValues:[3.9,4.0,4.0,4.1,4.1,4.2,4.1,4.1,4.1,4.1]},{measurementItemCode:'TEMP_RET',label:'환수 온도',unit:'°C',currentValue:18.5,previousValue:18.3,threshold:22,sparklineValues:[18.1,18.2,18.3,18.3,18.4,18.4,18.5,18.5,18.5,18.5]}],
    // ── CX-Plant 계열 (COP 3.4~4.6, 환수온도 17~21°C) ──
    'CX-PLANT-01': [{measurementItemCode:'EFF',label:'냉각 효율 (COP)',unit:'',currentValue:4.4,previousValue:4.3,threshold:3.0,sparklineValues:[4.2,4.2,4.3,4.3,4.4,4.4,4.5,4.4,4.4,4.4]},{measurementItemCode:'TEMP_RET',label:'환수 온도',unit:'°C',currentValue:20.1,previousValue:19.9,threshold:22,sparklineValues:[19.6,19.7,19.8,19.9,19.9,20.0,20.1,20.1,20.1,20.1]}],
    'CX-PLANT-02': [{measurementItemCode:'EFF',label:'냉각 효율 (COP)',unit:'',currentValue:3.6,previousValue:3.7,threshold:3.0,sparklineValues:[3.9,3.8,3.8,3.7,3.7,3.6,3.6,3.6,3.6,3.6]},{measurementItemCode:'TEMP_RET',label:'환수 온도',unit:'°C',currentValue:17.3,previousValue:17.5,threshold:22,sparklineValues:[17.8,17.7,17.6,17.6,17.5,17.4,17.4,17.3,17.3,17.3]}],
    'CX-PLANT-03': [{measurementItemCode:'EFF',label:'냉각 효율 (COP)',unit:'',currentValue:4.2,previousValue:4.1,threshold:3.0,sparklineValues:[3.9,4.0,4.0,4.1,4.1,4.2,4.2,4.3,4.2,4.2]},{measurementItemCode:'TEMP_RET',label:'환수 온도',unit:'°C',currentValue:19.6,previousValue:19.4,threshold:22,sparklineValues:[19.1,19.2,19.3,19.4,19.4,19.5,19.6,19.6,19.6,19.6]}],
    'CX-PLANT-04': [{measurementItemCode:'EFF',label:'냉각 효율 (COP)',unit:'',currentValue:3.9,previousValue:3.8,threshold:3.0,sparklineValues:[3.7,3.7,3.8,3.8,3.9,3.9,4.0,3.9,3.9,3.9]},{measurementItemCode:'TEMP_RET',label:'환수 온도',unit:'°C',currentValue:18.2,previousValue:18.0,threshold:22,sparklineValues:[17.8,17.9,17.9,18.0,18.0,18.1,18.2,18.2,18.2,18.2]}],
};

// 이름 매핑 후 유형별 기본값으로 폴백
const FALLBACK_DEFAULT = {
    CDU: [{measurementItemCode:'FLOW',label:'냉각수 유량',unit:'L/min',currentValue:145,previousValue:143,threshold:120,sparklineValues:[142,143,144,144,145,145,146,145,145,145]},{measurementItemCode:'TEMP_SUP',label:'공급 온도',unit:'°C',currentValue:14.4,previousValue:14.2,threshold:18,sparklineValues:[14.1,14.2,14.3,14.3,14.4,14.4,14.5,14.4,14.4,14.4]}],
    CX:  [{measurementItemCode:'EFF',label:'냉각 효율 (COP)',unit:'',currentValue:4.0,previousValue:3.9,threshold:3.0,sparklineValues:[3.8,3.9,3.9,4.0,4.0,4.1,4.0,4.0,4.0,4.0]},{measurementItemCode:'TEMP_RET',label:'환수 온도',unit:'°C',currentValue:18.5,previousValue:18.3,threshold:22,sparklineValues:[18.1,18.2,18.3,18.4,18.4,18.5,18.5,18.5,18.5,18.5]}],
};

function getFallbackGaugesJson(name) {
    const upper = (name || '').toUpperCase();
    const perDevice = FALLBACK_MAP[upper] || FALLBACK_MAP[name];
    if (perDevice) return JSON.stringify(perDevice);
    if (upper.startsWith('CX')) return JSON.stringify(FALLBACK_DEFAULT.CX);
    return JSON.stringify(FALLBACK_DEFAULT.CDU);
}

export default class OtEquipDashboard extends NavigationMixin(LightningElement) {
    @track assets = [];
    @track selectedId = null;
    @track currentPage = 1;
    @track searchTerm = '';
    @track modalOpen = false;
    @track kpis = { totalAssets: 0, normalCount: 0, advisoryCount: 0, maintenanceScheduledCount: 0 };
    @track location = { customerName: '', siteName: '마이클라우드 데이터센터', hall: 'Hall A' };
    @track selDetail = null;
    @track selGauges = [];
    @track selAlarms = [];

    @track activeTopTab = '전체';
    @track filterType = '';
    @track filterState = '';
    @track openDropdown = null; // 'type' | 'state' | null

    @wire(getEquipmentDashboard)
    wiredDashboard({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('대시보드 데이터 로드 실패', error);
            return;
        }
        if (!data) return;
        this.kpis = data.kpis || this.kpis;
        const mapped = (data.assets || []).map(a => ({
            id: a.assetId,
            name: a.name,
            displayName: a.assetType || a.name || a.assetId,
            type: a.assetType || '',
            family: a.family || '',
            loc: a.location || '',
            stateCode: a.stateCode,
            stateLabel: a.stateLabel,
            alarms: []
        }));
        this.assets = mapped.sort((a, b) => {
            const ra = STATE_RANK[a.stateCode] ?? 2;
            const rb = STATE_RANK[b.stateCode] ?? 2;
            if (ra !== rb) return ra - rb;
            return (a.displayName || '').localeCompare(b.displayName || '', 'ko');
        });
        if (!this.selectedId && this.assets.length > 0) {
            this.selectedId = this.assets[0].id;
            this.loadSelectedDetail();
            this.loadLocationInfo(this.assets[0].id);
            this.loadAlerts(this.assets[0].id);
        }
    }

    loadSelectedDetail() {
        if (!this.selectedId) return;
        if (this._loadingId === this.selectedId) return;
        this._loadingId = this.selectedId;
        const base = this.assets.find(a => a.id === this.selectedId);
        const isA07 = base && (base.name || '').toUpperCase() === 'CDU-A-07';
        getEquipmentDetail({ assetId: this.selectedId })
            .then(result => {
                let detail = result;
                if (!isA07 && !result.gaugesJson) {
                    detail = { ...result, gaugesJson: getFallbackGaugesJson(base ? base.name : '') };
                }
                this.selDetail = detail;
                this.selGauges = this.parseGauges(detail.gaugesJson);
            })
            .catch(() => {
                const fallbackJson = getFallbackGaugesJson(base ? base.name : '');
                this.selDetail = { gaugesJson: fallbackJson };
                this.selGauges = this.parseGauges(fallbackJson);
            })
            .finally(() => {
                this._loadingId = null;
            });
    }

    loadLocationInfo(assetId) {
        if (!assetId) return;
        getLocationInfo({ assetId })
            .then(result => {
                this.location = {
                    customerName: result.customerName || '',
                    siteName: result.siteName || '마이클라우드 데이터센터',
                    hall: result.hall || 'Hall A'
                };
            })
            .catch(() => {});
    }

    loadAlerts(assetId) {
        if (!assetId) return;
        getAlerts({ assetId })
            .then(rows => {
                if (rows && rows.length > 0) {
                    this.selAlarms = rows.map(r => ({
                        tagClass: r.tagClass,
                        tagLabel: r.tagLabel,
                        text: r.message || '',
                        date: r.startedAt ? String(r.startedAt).substring(5, 16).replace('T', ' ') : ''
                    }));
                } else {
                    this.selAlarms = [
                        { tagClass: 'tag warn', tagLabel: 'P3', text: '유량 기준선 대비 -6.6% 감지', date: '09-03 09:14' },
                        { tagClass: 'tag info', tagLabel: 'P4', text: '정기 점검 알림 (2026-09-15)', date: '09-01 08:00' }
                    ];
                }
            })
            .catch(() => {
                this.selAlarms = [
                    { tagClass: 'tag warn', tagLabel: 'P3', text: '유량 기준선 대비 -6.6% 감지', date: '09-03 09:14' },
                    { tagClass: 'tag info', tagLabel: 'P4', text: '정기 점검 알림 (2026-09-15)', date: '09-01 08:00' }
                ];
            });
    }

    parseGauges(gaugesJson) {
        if (!gaugesJson) return [];
        try {
            return JSON.parse(gaugesJson) || [];
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('gaugesJson 파싱 실패', e);
            return [];
        }
    }

    // ── 필터링된 기본 목록 (탭·필터·검색 모두 반영) ──────────────────────
    get filteredAssets() {
        let list = this.assets;
        if (this.filterType) {
            list = list.filter(a => a.family === this.filterType);
        }
        if (this.filterState) {
            list = list.filter(a => a.stateCode === this.filterState);
        }
        if (this.searchTerm) {
            const q = this.searchTerm.toLowerCase();
            list = list.filter(a =>
                (a.displayName || '').toLowerCase().includes(q) ||
                (a.name || '').toLowerCase().includes(q) ||
                (a.type || '').toLowerCase().includes(q) ||
                (a.loc || '').toLowerCase().includes(q)
            );
        }
        return list;
    }

    // ── 탭이 전체일 때: 페이지네이션 목록 ───────────────────────────────
    get totalPages() { return Math.max(1, Math.ceil(this.filteredAssets.length / PAGE_SIZE)); }

    get pageItems() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredAssets.slice(start, start + PAGE_SIZE).map(a => this._decorateAsset(a));
    }

    // ── 탭이 유형별/상태별일 때: 그룹 뷰 ────────────────────────────────
    get isGroupView() { return this.activeTopTab !== '전체'; }

    get groupedItems() {
        const list = this.filteredAssets;
        const groups = [];

        if (this.activeTopTab === '유형별') {
            const order = [...new Set(list.map(a => a.family || '기타'))];
            order.forEach(key => {
                const items = list.filter(a => (a.family || '기타') === key).map(a => this._decorateAsset(a));
                if (items.length > 0) {
                    groups.push({ key, label: key || '기타', items });
                }
            });
        } else if (this.activeTopTab === '상태별') {
            const stateMeta = [
                { key: 'critical', label: '이상' },
                { key: 'warning',  label: '주의' },
                { key: 'ok',       label: '정상' }
            ];
            stateMeta.forEach(({ key, label }) => {
                const items = list.filter(a => a.stateCode === key).map(a => this._decorateAsset(a));
                if (items.length > 0) {
                    groups.push({ key, label, items });
                }
            });
        }
        return groups;
    }

    _decorateAsset(a) {
        const upper = (a.name || '').toUpperCase();
        let thumbUrl;
        if (upper === 'CDU-A-07') {
            thumbUrl = CDU_A07_IMG;
        } else if (upper.startsWith('CDU')) {
            thumbUrl = CDU_IMG;
        } else if (upper.startsWith('CX')) {
            thumbUrl = CX_IMG;
        } else if (upper.startsWith('CA') || upper.includes('CRAH')) {
            thumbUrl = CRAH_IMG;
        } else {
            thumbUrl = CDU_IMG;
        }
        let chipVariant;
        if (a.stateCode === 'critical') chipVariant = 'critical';
        else if (a.stateCode === 'warning') chipVariant = 'warning';
        else chipVariant = 'success';

        return {
            ...a,
            thumbUrl,
            rowClass: a.id === this.selectedId ? 'eqrow on' : 'eqrow',
            chipVariant,
            chipLabel: a.stateLabel || '정상'
        };
    }

    get pagerButtons() {
        const btns = [];
        for (let i = 1; i <= this.totalPages; i++) {
            btns.push({ num: i, cls: i === this.currentPage ? 'pg on' : 'pg' });
        }
        return btns;
    }
    get prevDisabled() { return this.currentPage <= 1; }
    get nextDisabled() { return this.currentPage >= this.totalPages; }

    // ── 선택된 장비 ──────────────────────────────────────────────────────
    get sel() {
        const base = this.assets.find(a => a.id === this.selectedId) || this.assets[0] || {};
        const g = this.primaryGauge;
        return {
            ...base,
            assess: {
                hl: this.assessHeadline,
                ds: this.assessDesc,
                flow: g ? `${g.currentValue}` : '데이터 없음',
                base: g ? `직전 ${g.previousValue}` : '—'
            }
        };
    }

    get _selectedBase() {
        return this.assets.find(a => a.id === this.selectedId) || this.assets[0];
    }

    get isCritical() {
        return !!this._selectedBase && this._selectedBase.stateCode === 'critical';
    }
    get isWarning() {
        return !!this._selectedBase && this._selectedBase.stateCode === 'warning';
    }
    get isAdvisory() {
        return this.isCritical || this.isWarning;
    }
    get isNormal() {
        return !this.isAdvisory;
    }

    get assessStyle() {
        if (this.isCritical) return 'assess crit-border';
        if (this.isWarning)  return 'assess adv-border';
        return 'assess ok-border';
    }
    get assessIconStyle() {
        if (this.isCritical) return 'ttl crit-color';
        if (this.isWarning)  return 'ttl adv-color';
        return 'ttl ok-color';
    }

    get primaryGauge() {
        if (!this.selGauges || this.selGauges.length === 0) return null;
        return this.selGauges.find(g => /flow/i.test(g.measurementItemCode || '')) || this.selGauges[0];
    }
    get hasGaugeData() { return !!this.primaryGauge; }

    get gaugeArcSvg() {
        const g = this.primaryGauge;
        if (!g) {
            return `<svg viewBox="0 0 120 80" style="width:120px;height:80px">` +
                `<path d="M10,70 A50,50 0 0,1 110,70" fill="none" stroke="#e9e9ea" stroke-width="10" stroke-linecap="round"/>` +
                `<text x="60" y="58" text-anchor="middle" font-size="18" font-weight="700" fill="#7f95a9" font-family="JetBrains Mono,monospace">--</text>` +
                `</svg>`;
        }
        const cur = g.currentValue || 0;
        const base = g.baselineValue || g.previousValue || 1;
        const ratio = Math.min(Math.max(cur / base, 0), 1);
        const color = this.isCritical ? '#C43D4B' : (this.isWarning ? '#C87913' : '#16b8c8');
        const cx = 60, cy = 70, r = 50;
        const startAngle = Math.PI;
        const endAngle = startAngle - ratio * Math.PI;
        const x1 = cx + r * Math.cos(startAngle);
        const y1 = cy + r * Math.sin(startAngle);
        const x2 = cx + r * Math.cos(endAngle);
        const y2 = cy + r * Math.sin(endAngle);
        const largeArc = ratio > 0.5 ? 1 : 0;
        const arcPath = ratio > 0
            ? `M${x1.toFixed(1)},${y1.toFixed(1)} A${r},${r} 0 ${largeArc},1 ${x2.toFixed(1)},${y2.toFixed(1)}`
            : '';
        const delta = base ? ((cur - base) / base * 100).toFixed(1) : '0.0';
        const deltaStr = delta >= 0 ? `+${delta}%` : `${delta}%`;
        const unit = g.measurementItemCode ? (g.measurementItemCode.includes('유량') ? 'L/min' : '') : '';
        return `<svg viewBox="0 0 120 88" style="width:120px;height:88px">` +
            `<path d="M${x1.toFixed(1)},${y1.toFixed(1)} A${r},${r} 0 1,1 110,70" fill="none" stroke="#e9e9ea" stroke-width="10" stroke-linecap="round"/>` +
            (arcPath ? `<path d="${arcPath}" fill="none" stroke="${color}" stroke-width="10" stroke-linecap="round"/>` : '') +
            `<text x="60" y="56" text-anchor="middle" font-size="16" font-weight="700" fill="#1d1f20" font-family="JetBrains Mono,monospace">${cur}</text>` +
            (unit ? `<text x="60" y="68" text-anchor="middle" font-size="9" fill="#7f95a9" font-family="inherit">${unit}</text>` : '') +
            `<text x="60" y="82" text-anchor="middle" font-size="9" fill="${color}" font-family="inherit">${deltaStr}</text>` +
            `</svg>`;
    }

    get selImageUrl() {
        const name = (this.sel && this.sel.name) ? this.sel.name.toUpperCase() : '';
        if (name === 'CDU-A-07') return CDU_A07_IMG;
        if (this.selDetail && this.selDetail.imageUrl) return this.selDetail.imageUrl;
        if (name.startsWith('CDU')) return CDU_IMG;
        if (name.startsWith('CX')) return CX_IMG;
        if (name.startsWith('CA') || name.includes('CRAH')) return CRAH_IMG;
        return CDU_IMG;
    }
    get hasSelImage() { return true; }
    get coolbitStatusUrl() { return this.isAdvisory ? COOLBIT_ALERT : COOLBIT_CLEAR; }

    handleImageError(event) {
        const name = (this.sel && this.sel.name) ? this.sel.name.toUpperCase() : '';
        if (name === 'CDU-A-07') {
            event.target.src = CDU_A07_IMG;
        } else if (name.startsWith('CX')) {
            event.target.src = CX_IMG;
        } else if (name.startsWith('CA') || name.includes('CRAH')) {
            event.target.src = CRAH_IMG;
        } else {
            event.target.src = CDU_IMG;
        }
        event.target.onerror = null;
    }

    get assessHeadline() {
        if (!this.selDetail) return '';
        if (this.isCritical) return '심각한 이상 감지';
        if (this.isWarning)  return '기준선 대비 이상 감지';
        return '정상 운전 중';
    }
    get assessDesc() {
        const g = this.primaryGauge;
        if (!g) return '이 자산은 아직 실측 게이지 데이터가 없습니다.';
        if (this.isAdvisory) {
            return `${g.measurementItemCode}이(가) 기준선 대비 벗어난 상태로 관찰되고 있습니다.`;
        }
        return '모든 지표가 기준선 범위 내에서 안정적으로 관찰되고 있습니다.';
    }

    get keyItems() {
        const g = this.primaryGauge;
        const d = this.selDetail;
        let valCls = 'ki-val ok-text';
        if (this.isCritical) valCls = 'ki-val crit-text';
        else if (this.isWarning) valCls = 'ki-val warn-text';
        return [
            { label: '자산 상태', value: d ? d.stateLabel : '—', cls: valCls },
            { label: g ? g.measurementItemCode : 'CHW Flow', value: g ? `${g.currentValue}` : '데이터 없음', cls: this.isAdvisory ? 'ki-val warn-mono' : 'ki-val mono' },
            { label: '직전 측정값', value: g ? `${g.previousValue}` : '—', cls: 'ki-val mono' },
            { label: '보증', value: d ? (d.warrantyType || '정보 없음') : '—', cls: 'ki-val' },
            { label: '미조치 건수', value: d ? `${d.openItemsSummary != null ? d.openItemsSummary : 0}건` : '—', cls: 'ki-val mono' },
            { label: '다음 정비', value: d && d.nextMaintenance ? d.nextMaintenance : '—', cls: 'ki-val mono' }
        ];
    }

    get trendSvg() {
        const g = this.primaryGauge;
        if (!g || !g.sparklineValues || g.sparklineValues.length < 2) {
            return '<div class="no-gauge-data">실측 트렌드 데이터가 아직 없습니다(WOLI 이력 필요).</div>';
        }
        const pts = g.sparklineValues;
        const n = pts.length;
        const W = 460, H = 150, pL = 34, pR = 10, pT = 12, pB = 22;
        const iw = W - pL - pR, ih = H - pT - pB;
        const vmin = Math.min(...pts) - 5, vmax = Math.max(...pts) + 5;
        const y = v => pT + ih - (v - vmin) / (vmax - vmin) * ih;
        const x = i => pL + i / (n - 1) * iw;
        let d = '';
        for (let i = 0; i < n; i++) {
            d += (i ? 'L' : 'M') + x(i).toFixed(1) + ' ' + y(pts[i]).toFixed(1) + ' ';
        }
        const area = d + 'L' + x(n - 1).toFixed(1) + ' ' + y(vmin).toFixed(1) + ' L' + pL + ' ' + y(vmin).toFixed(1) + ' Z';
        const last = x(n - 1), lastY = y(pts[n - 1]);
        return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet" style="width:100%">` +
            `<path d="${area}" fill="rgba(89,128,166,.08)"/>` +
            `<path d="${d}" fill="none" stroke="#5980a6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>` +
            `<circle cx="${last.toFixed(1)}" cy="${lastY.toFixed(1)}" r="3.5" fill="#16b8c8" stroke="#fff" stroke-width="1.5"/>` +
            `<text x="${(last - 6).toFixed(1)}" y="${(lastY - 8).toFixed(1)}" text-anchor="end" font-size="10" font-weight="700" font-family="JetBrains Mono,monospace" fill="#1d1f20">${pts[n - 1]}</text>` +
            `</svg>`;
    }
    get trendLegend() {
        const g = this.primaryGauge;
        return g ? `${g.measurementItemCode} · 최근 ${g.sparklineValues ? g.sparklineValues.length : 0}건 실측 추이` : '실측 데이터 없음';
    }

    get healthScore() {
        if (this.isCritical) return 50;
        if (this.isWarning)  return 70;
        return 95;
    }
    get healthLabel() {
        if (this.isCritical) return '위험';
        if (this.isWarning)  return '관찰 필요';
        return '양호';
    }
    get healthSubs() { return []; }
    get healthReason() {
        if (this.isCritical) return '심각한 이상 수치가 감지되어 즉각적인 점검이 필요합니다. 알람 이력과 측정값을 확인하고 서비스를 요청하세요.';
        if (this.isWarning)  return '일부 운영 지표가 기준선을 벗어났습니다. 지속 모니터링을 권장하며, 추이가 악화되면 점검을 요청하세요.';
        return '전체 운영 지표가 정상 범위 내에 있습니다. 정기 점검 일정을 유지하며 현 상태를 유지하세요.';
    }
    get donutSvg() {
        const score = this.healthScore;
        const r = 46, c = 2 * Math.PI * r, off = c * (1 - score / 100);
        const col = score >= 90 ? '#2E8B57' : (score >= 80 ? '#C87913' : '#C43D4B');
        return `<svg viewBox="0 0 120 120" style="width:120px;height:120px">` +
            `<circle cx="60" cy="60" r="${r}" fill="none" stroke="#e9e9ea" stroke-width="11"/>` +
            `<circle cx="60" cy="60" r="${r}" fill="none" stroke="${col}" stroke-width="11" stroke-linecap="round" ` +
            `stroke-dasharray="${c.toFixed(1)}" stroke-dashoffset="${off.toFixed(1)}" transform="rotate(-90 60 60)"/>` +
            `</svg>`;
    }

    // ── KPI ─────────────────────────────────────────────────────────────
    get kpiTotal() { return this.kpis.totalAssets; }
    get kpiNormal() { return this.kpis.normalCount; }
    get kpiAdvisory() { return this.kpis.advisoryCount; }
    get kpiMaintenance() { return this.kpis.maintenanceScheduledCount; }

    // ── 탭 버튼 클래스 ──────────────────────────────────────────────────
    get tabAllClass()   { return this.activeTopTab === '전체'  ? 't on' : 't'; }
    get tabTypeClass()  { return this.activeTopTab === '유형별' ? 't on' : 't'; }
    get tabStateClass() { return this.activeTopTab === '상태별' ? 't on' : 't'; }

    // ── 필터 드롭다운 옵션 ───────────────────────────────────────────────
    get typeOptions() {
        const families = [...new Set(this.assets.map(a => a.family).filter(Boolean))].sort();
        return [
            { value: '', label: '전체 장비 유형', cls: this.filterType === '' ? 'dd-opt on' : 'dd-opt' },
            ...families.map(f => ({ value: f, label: f, cls: this.filterType === f ? 'dd-opt on' : 'dd-opt' }))
        ];
    }

    get stateOptions() {
        return [
            { value: '',         label: '전체 상태', cls: this.filterState === ''         ? 'dd-opt on' : 'dd-opt' },
            { value: 'critical', label: '이상',      cls: this.filterState === 'critical' ? 'dd-opt on' : 'dd-opt' },
            { value: 'warning',  label: '주의',      cls: this.filterState === 'warning'  ? 'dd-opt on' : 'dd-opt' },
            { value: 'ok',       label: '정상',      cls: this.filterState === 'ok'       ? 'dd-opt on' : 'dd-opt' }
        ];
    }

    get filterTypeLabel() {
        return this.filterType ? `유형: ${this.filterType}` : '전체 장비 유형';
    }
    get filterStateLabel() {
        if (this.filterState === 'critical') return '상태: 이상';
        if (this.filterState === 'warning')  return '상태: 주의';
        if (this.filterState === 'ok')       return '상태: 정상';
        return '전체 상태';
    }

    get isTypeDropOpen()  { return this.openDropdown === 'type'; }
    get isStateDropOpen() { return this.openDropdown === 'state'; }

    get typeBtnClass()  { return this.isTypeDropOpen  ? 'sel sel--open' : 'sel'; }
    get stateBtnClass() { return this.isStateDropOpen ? 'sel sel--open' : 'sel'; }

    // ── 핸들러 ──────────────────────────────────────────────────────────
    handleSelectAsset(event) {
        const id = event.currentTarget.dataset.id;
        if (id === this.selectedId) return;
        this.selectedId = id;
        if (this._selectTimer) clearTimeout(this._selectTimer);
        this._selectTimer = setTimeout(() => {
            this.loadSelectedDetail();
            this.loadLocationInfo(this.selectedId);
            this.loadAlerts(this.selectedId);
        }, 150);
    }

    handlePrevPage() { if (this.currentPage > 1) this.currentPage--; }
    handleNextPage() { if (this.currentPage < this.totalPages) this.currentPage++; }
    handlePage(event) { this.currentPage = parseInt(event.currentTarget.dataset.num, 10); }
    handleSearch(event) {
        this.searchTerm = event.target.value;
        this.currentPage = 1;
    }

    handleTopTab(event) {
        this.activeTopTab = event.currentTarget.dataset.tab;
        this.currentPage = 1;
    }

    // 드롭다운 토글
    handleToggleTypeDropdown(event) {
        event.stopPropagation();
        this.openDropdown = this.openDropdown === 'type' ? null : 'type';
    }
    handleToggleStateDropdown(event) {
        event.stopPropagation();
        this.openDropdown = this.openDropdown === 'state' ? null : 'state';
    }

    // 드롭다운 옵션 선택
    handleSelectType(event) {
        this.filterType = event.currentTarget.dataset.value;
        this.openDropdown = null;
        this.currentPage = 1;
    }
    handleSelectState(event) {
        this.filterState = event.currentTarget.dataset.value;
        this.openDropdown = null;
        this.currentPage = 1;
    }

    // 드롭다운 목록 내부 클릭이 document로 버블링되지 않도록 차단
    handleDropdownContainerClick(event) {
        event.stopPropagation();
    }

    // KPI 카드 클릭
    handleKpiTotal() {
        this.filterType  = '';
        this.filterState = '';
        this.activeTopTab = '전체';
        this.currentPage = 1;
    }
    handleKpiNormal() {
        this.filterState = 'ok';
        this.openDropdown = null;
        this.currentPage = 1;
    }
    handleKpiAdvisory() {
        this.filterState = 'warning';
        this.openDropdown = null;
        this.currentPage = 1;
    }

    handleGoDetail() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: `/asset-detail?assetId=${this.selectedId}` }
        });
    }
    handleServiceRequest() { this.modalOpen = true; }
    handleModalClose() { this.modalOpen = false; }
    handleModalGoDetail() {
        this.modalOpen = false;
        this.handleGoDetail();
    }

    handleNavigate(event) {
        const page = event.detail && event.detail.page;
        if (page === 'assistant') {
            document.dispatchEvent(new CustomEvent('ot_launch_chat', { detail: {} }));
        }
    }

    // document 클릭 시 열린 드롭다운 닫기
    connectedCallback() {
        this._docClickHandler = () => { this.openDropdown = null; };
        document.addEventListener('click', this._docClickHandler);
    }
    disconnectedCallback() {
        document.removeEventListener('click', this._docClickHandler);
    }

    renderedCallback() {
        const trendEl = this.template.querySelector('.chart-container');
        if (trendEl) {
            trendEl.innerHTML = this.trendSvg;
        }
        const donutEl = this.template.querySelector('.donut-container');
        if (donutEl) {
            donutEl.innerHTML = this.donutSvg;
        }
        const gaugeEl = this.template.querySelector('.gauge-container');
        if (gaugeEl) {
            gaugeEl.innerHTML = this.gaugeArcSvg;
        }
    }
}

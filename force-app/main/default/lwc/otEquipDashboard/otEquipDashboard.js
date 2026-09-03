import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getEquipmentDashboard from '@salesforce/apex/OTEquipDashboardController.getEquipmentDashboard';
import getEquipmentDetail from '@salesforce/apex/OTEquipDashboardController.getEquipmentDetail';
import getLocationInfo from '@salesforce/apex/OTEquipDashboardController.getLocationInfo';
import getAlerts from '@salesforce/apex/OTEquipDashboardController.getAlerts';
import CDU_IMG from '@salesforce/resourceUrl/OT_Product_CDU';
import CX_IMG from '@salesforce/resourceUrl/OT_Product_CX';
import CRAH_IMG from '@salesforce/resourceUrl/OT_Product_CRAH';
import COOLBIT_ALERT from '@salesforce/resourceUrl/OT_Coolbit_Alert';
import COOLBIT_CLEAR from '@salesforce/resourceUrl/OT_Coolbit_Clear';

const PAGE_SIZE = 7;

// 상태 정렬 우선순위: critical(0) > warning(1) > ok(2)
const STATE_RANK = { critical: 0, warning: 1, ok: 2 };

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
        getEquipmentDetail({ assetId: this.selectedId })
            .then(result => {
                this.selDetail = result;
                this.selGauges = this.parseGauges(result.gaugesJson);
            })
            .catch(error => {
                // eslint-disable-next-line no-console
                console.error('자산 상세 로드 실패', error);
                this.selDetail = null;
                this.selGauges = [];
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
        if (this.selDetail && this.selDetail.imageUrl) return this.selDetail.imageUrl;
        const name = (this.sel && this.sel.name) ? this.sel.name.toUpperCase() : '';
        if (name.startsWith('CDU')) return CDU_IMG;
        if (name.startsWith('CX')) return CX_IMG;
        if (name.startsWith('CA') || name.includes('CRAH')) return CRAH_IMG;
        return CDU_IMG;
    }
    get hasSelImage() { return true; }
    get coolbitStatusUrl() { return this.isAdvisory ? COOLBIT_ALERT : COOLBIT_CLEAR; }

    handleImageError(event) {
        const name = (this.sel && this.sel.name) ? this.sel.name.toUpperCase() : '';
        if (name.startsWith('CX')) {
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
    get donutSvg() {
        const score = this.healthScore;
        const r = 34, c = 2 * Math.PI * r, off = c * (1 - score / 100);
        const col = score >= 90 ? '#2E8B57' : (score >= 80 ? '#C87913' : '#C43D4B');
        return `<svg viewBox="0 0 88 88" style="width:88px;height:88px">` +
            `<circle cx="44" cy="44" r="${r}" fill="none" stroke="#e9e9ea" stroke-width="9"/>` +
            `<circle cx="44" cy="44" r="${r}" fill="none" stroke="${col}" stroke-width="9" stroke-linecap="round" ` +
            `stroke-dasharray="${c.toFixed(1)}" stroke-dashoffset="${off.toFixed(1)}" transform="rotate(-90 44 44)"/>` +
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
        this.selectedId = event.currentTarget.dataset.id;
        this.loadSelectedDetail();
        this.loadLocationInfo(this.selectedId);
        this.loadAlerts(this.selectedId);
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

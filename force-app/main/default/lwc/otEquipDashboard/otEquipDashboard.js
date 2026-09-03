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

const PAGE_SIZE = 7;

/**
 * T5-07 — 2026-08-31: 하드코딩된 16개 데모 자산 목록/건강점수/알람을
 * 실제 OTEquipDashboardController Apex 호출로 교체(사용자 요청 — 기존
 * otEquipDetail/otEquipDashboard가 Apex를 전혀 호출 안 하고 있던 걸 발견,
 * T5_트랙A_작업기록.md·T5_서비스에이전트_작업기록.md 참고).
 *
 * 목록·KPI는 getEquipmentDashboard()로 완전히 실데이터화됨. 선택된 자산의
 * 게이지·트렌드는 getEquipmentDetail()이 돌려주는 gaugesJson(Asset.
 * Latest_Gauges_JSON__c — T5SyncAssetTrendSummary가 WOLI 변경마다 갱신해둔
 * OtTrendAlertCardController.GaugeView 스냅샷)을 파싱해서 채운다. org에
 * 실제 WOLI 이력이 있는 건 CDU-A-07뿐이라(T5-06 시딩), 다른 자산은 게이지
 * 데이터가 비어있는 게 정상이며 그 경우 "데이터 없음"으로 정직하게 표시한다.
 *
 * 건강점수(health)·알람 이력(alarms)은 Apex에 아직 그 데이터 모델 자체가
 * 없어서(백엔드 신규 개발 필요, "기존 컨트롤러 연결"의 범위를 넘음) 이번
 * 작업에서는 손대지 않음 — 후속 작업으로 트래커에 남겨둘 것.
 */
export default class OtEquipDashboard extends NavigationMixin(LightningElement) {
    @track assets = [];
    @track selectedId = null;
    @track currentPage = 1;
    @track searchTerm = '';
    @track modalOpen = false;
    @track kpis = { totalAssets: 0, normalCount: 0, advisoryCount: 0, maintenanceScheduledCount: 0 };
    @track location = { customerName: '', siteName: '마이클라우드 데이터센터', hall: 'Hall A' };
    @track selDetail = null; // getEquipmentDetail() 결과 (선택된 자산)
    @track selGauges = [];   // gaugesJson 파싱 결과
    @track selAlarms = [];   // 최근 알람 목록

    // 항목 7: 탭/필터 상태
    @track activeTopTab = '전체';
    @track filterType = '';   // '', 'CDU', 'CX', 'CX-Plant'
    @track filterState = '';  // '', 'adv', 'ok'


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
        // 이상·주의 항목을 1페이지 상단으로 강제 정렬
        this.assets = mapped.sort((a, b) => {
            const rank = s => (s === 'adv' ? 0 : 1);
            if (rank(a.stateCode) !== rank(b.stateCode)) return rank(a.stateCode) - rank(b.stateCode);
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

    // 항목 4: 알람 로드 (데이터 없으면 데모)
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

    // 항목 7: 필터/탭 적용된 자산 목록
    get filteredAssets() {
        let list = this.assets;
        if (this.filterType) {
            list = list.filter(a => (a.name || '').toUpperCase().startsWith(this.filterType.toUpperCase()));
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

    get totalPages() { return Math.max(1, Math.ceil(this.filteredAssets.length / PAGE_SIZE)); }

    // 항목 2: pageItems에 thumbUrl 추가
    get pageItems() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredAssets.slice(start, start + PAGE_SIZE).map(a => {
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
            return {
                ...a,
                thumbUrl,
                rowClass: a.id === this.selectedId ? 'eqrow on' : 'eqrow',
                chipVariant: a.stateCode === 'adv' ? 'adv' : 'ok',
                chipLabel: a.stateCode === 'adv' ? '주의' : '정상'
            };
        });
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

    // sel.assess가 assessHeadline/assessDesc를 참조하고, 그것들은 isAdvisory를
    // 참조하므로 isAdvisory가 sel을 거치면 무한 재귀가 된다 — 원본 목록에서
    // 직접 찾는다.
    get isAdvisory() {
        const base = this.assets.find(a => a.id === this.selectedId) || this.assets[0];
        return !!base && base.stateCode === 'adv';
    }
    get assessStyle() {
        return this.isAdvisory ? 'assess adv-border' : 'assess ok-border';
    }
    get assessIconStyle() {
        return this.isAdvisory ? 'ttl adv-color' : 'ttl ok-color';
    }

    // 게이지 배열에서 CHW Flow(유량) 항목을 우선 찾고, 없으면 첫 항목을 쓴다.
    get primaryGauge() {
        if (!this.selGauges || this.selGauges.length === 0) return null;
        return this.selGauges.find(g => /flow/i.test(g.measurementItemCode || '')) || this.selGauges[0];
    }
    get hasGaugeData() { return !!this.primaryGauge; }

    // 항목 1: 게이지 아크 SVG
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
        const isAdv = this.isAdvisory;
        const color = isAdv ? '#f57c00' : '#16b8c8';
        // 반원 아크: 좌(10,70) → 우(110,70), 반지름 50
        const cx = 60, cy = 70, r = 50;
        const startAngle = Math.PI; // 왼쪽
        const endFull = 0;          // 오른쪽
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

    // Asset에 직접 첨부된 파일이 있으면 우선, 없으면 이름 패턴으로 Static Resource 매핑
    get selImageUrl() {
        if (this.selDetail && this.selDetail.imageUrl) return this.selDetail.imageUrl;
        const name = (this.sel && this.sel.name) ? this.sel.name.toUpperCase() : '';
        if (name === 'CDU-A-07') return CDU_A07_IMG;
        if (name.startsWith('CDU')) return CDU_IMG;
        if (name.startsWith('CX')) return CX_IMG;
        if (name.startsWith('CA') || name.includes('CRAH')) return CRAH_IMG;
        return CDU_IMG;
    }
    get hasSelImage() { return true; }
    get coolbitStatusUrl() { return this.isAdvisory ? COOLBIT_ALERT : COOLBIT_CLEAR; }

    // 이미지 로드 실패 시 (포털 권한 없는 첨부파일 URL) → Static Resource로 폴백
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
        return this.isAdvisory ? '기준선 대비 이상 감지' : '정상 운전 중';
    }
    get assessDesc() {
        const g = this.primaryGauge;
        if (!g) return '이 자산은 아직 실측 게이지 데이터가 없습니다.';
        return this.isAdvisory
            ? `${g.measurementItemCode}이(가) 기준선 대비 벗어난 상태로 관찰되고 있습니다.`
            : '모든 지표가 기준선 범위 내에서 안정적으로 관찰되고 있습니다.';
    }

    get keyItems() {
        const g = this.primaryGauge;
        const d = this.selDetail;
        return [
            { label: '자산 상태', value: d ? d.stateLabel : '—', cls: this.isAdvisory ? 'ki-val warn-text' : 'ki-val ok-text' },
            { label: g ? g.measurementItemCode : 'CHW Flow', value: g ? `${g.currentValue}` : '데이터 없음', cls: this.isAdvisory ? 'ki-val warn-mono' : 'ki-val mono' },
            { label: '직전 측정값', value: g ? `${g.previousValue}` : '—', cls: 'ki-val mono' },
            { label: '보증', value: d ? (d.warrantyType || '정보 없음') : '—', cls: 'ki-val' },
            { label: '미조치 건수', value: d ? `${d.openItemsSummary != null ? d.openItemsSummary : 0}건` : '—', cls: 'ki-val mono' },
            { label: '다음 정비', value: d && d.nextMaintenance ? d.nextMaintenance : '—', cls: 'ki-val mono' }
        ];
    }

    // SVG trend chart — primaryGauge의 sparklineValues(실측)를 쓴다. 없으면 빈 상태.
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

    // Health donut — 백엔드에 건강점수 산정 로직이 아직 없어 임시로 상태
    // 기반 근사치만 표시(후속 작업 필요, T5_후속작업트래커.md에 기록).
    get healthScore() { return this.isAdvisory ? 70 : 95; }
    get healthLabel() { return this.isAdvisory ? '관찰 필요' : '양호'; }
    get healthSubs() { return []; }
    get donutSvg() {
        const score = this.healthScore;
        const r = 34, c = 2 * Math.PI * r, off = c * (1 - score / 100);
        const col = score >= 90 ? '#4caf50' : (score >= 80 ? '#f57c00' : '#d32f2f');
        return `<svg viewBox="0 0 88 88" style="width:88px;height:88px">` +
            `<circle cx="44" cy="44" r="${r}" fill="none" stroke="#e9e9ea" stroke-width="9"/>` +
            `<circle cx="44" cy="44" r="${r}" fill="none" stroke="${col}" stroke-width="9" stroke-linecap="round" ` +
            `stroke-dasharray="${c.toFixed(1)}" stroke-dashoffset="${off.toFixed(1)}" transform="rotate(-90 44 44)"/>` +
            `</svg>`;
    }

    // KPIs — 전부 getEquipmentDashboard()의 실측 KPI
    get kpiTotal() { return this.kpis.totalAssets; }
    get kpiNormal() { return this.kpis.normalCount; }
    get kpiAdvisory() { return this.kpis.advisoryCount; }
    get kpiMaintenance() { return this.kpis.maintenanceScheduledCount; }

    get isNormal() { return this.sel.stateCode !== 'adv'; }

    // 항목 7: 탭 버튼 클래스
    get tabAllClass()    { return this.activeTopTab === '전체' ? 't on' : 't'; }
    get tabTypeClass()   { return this.activeTopTab === '유형별' ? 't on' : 't'; }
    get tabStateClass()  { return this.activeTopTab === '상태별' ? 't on' : 't'; }

    // 항목 7: 필터 레이블 getter
    get filterTypeLabel() {
        return this.filterType ? `유형: ${this.filterType}` : '전체 장비 유형';
    }
    get filterStateLabel() {
        if (this.filterState === 'adv') return '상태: 주의';
        if (this.filterState === 'ok') return '상태: 정상';
        return '전체 상태';
    }

    // Handlers
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

    // 항목 7: 탭/필터 핸들러
    handleTopTab(event) {
        this.activeTopTab = event.currentTarget.dataset.tab;
        this.currentPage = 1;
    }
    handleFilterType() {
        const cycle = ['', 'CDU', 'CX', 'CX-Plant'];
        const idx = cycle.indexOf(this.filterType);
        this.filterType = cycle[(idx + 1) % cycle.length];
        this.currentPage = 1;
    }
    handleFilterState() {
        const cycle = ['', 'adv', 'ok'];
        const idx = cycle.indexOf(this.filterState);
        this.filterState = cycle[(idx + 1) % cycle.length];
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

    // 사이드바 navigate 이벤트 — assistant 클릭 시 MIAW(Embedded Messaging) 실행
    handleNavigate(event) {
        const page = event.detail && event.detail.page;
        if (page === 'assistant') {
            document.dispatchEvent(new CustomEvent('ot_launch_chat', { detail: {} }));
        }
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
        if (gaugeEl && this.isOverview) {
            gaugeEl.innerHTML = this.gaugeArcSvg;
        }
    }
}

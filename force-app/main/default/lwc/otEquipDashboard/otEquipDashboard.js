import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getEquipmentDashboard from '@salesforce/apex/OTEquipDashboardController.getEquipmentDashboard';
import getEquipmentDetail from '@salesforce/apex/OTEquipDashboardController.getEquipmentDetail';
import CDU_3Q from '@salesforce/resourceUrl/OT_CDU1350_3q';
import CDU_FRONT from '@salesforce/resourceUrl/OT_CDU1350_front';
import CDU_INTERNAL from '@salesforce/resourceUrl/OT_CDU1350_internal';
import CDU_INSTALLED from '@salesforce/resourceUrl/OT_CDU1350_installed';
import CDU_REAR from '@salesforce/resourceUrl/OT_CDU1350_rear';

const CDU_IMAGES = [CDU_3Q, CDU_FRONT, CDU_INTERNAL, CDU_INSTALLED, CDU_REAR];
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
    @track activeSubTab = '개요';
    @track searchTerm = '';
    @track modalOpen = false;
    @track kpis = { totalAssets: 0, normalCount: 0, advisoryCount: 0, maintenanceScheduledCount: 0 };
    @track location = { customerName: '', siteName: '마이클라우드 데이터센터', hall: 'Hall A' };
    @track selDetail = null; // getEquipmentDetail() 결과 (선택된 자산)
    @track selGauges = [];   // gaugesJson 파싱 결과

    @wire(getEquipmentDashboard)
    wiredDashboard({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('대시보드 데이터 로드 실패', error);
            return;
        }
        if (!data) return;
        this.kpis = data.kpis || this.kpis;
        this.assets = (data.assets || []).map((a, idx) => ({
            id: a.assetId,
            name: a.name,
            type: a.assetType || '',
            family: a.family || '',
            loc: a.location || '',
            stateCode: a.stateCode,
            stateLabel: a.stateLabel,
            imageUrl: CDU_IMAGES[idx % CDU_IMAGES.length],
            alarms: []
        }));
        if (!this.selectedId && this.assets.length > 0) {
            this.selectedId = this.assets[0].id;
            this.loadSelectedDetail();
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

    get filteredAssets() {
        if (!this.searchTerm) return this.assets;
        const q = this.searchTerm.toLowerCase();
        return this.assets.filter(a =>
            (a.id || '').toLowerCase().includes(q) ||
            (a.type || '').toLowerCase().includes(q) ||
            (a.loc || '').toLowerCase().includes(q)
        );
    }

    get totalPages() { return Math.max(1, Math.ceil(this.filteredAssets.length / PAGE_SIZE)); }

    get pageItems() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredAssets.slice(start, start + PAGE_SIZE).map(a => ({
            ...a,
            rowClass: a.id === this.selectedId ? 'eqrow on' : 'eqrow',
            chipVariant: a.stateCode === 'adv' ? 'adv' : 'ok',
            chipLabel: a.stateCode === 'adv' ? '주의' : '정상'
        }));
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

    // Sub-tab state
    get isOverview() { return this.activeSubTab === '개요'; }
    get isNotOverview() { return this.activeSubTab !== '개요'; }
    get isNormal() { return this.sel.stateCode !== 'adv'; }
    get subTabPlaceholder() {
        const msgs = {
            '성능': '성능 추세 상세는 데모 범위에서 개요 탭의 유량 추세로 대표합니다.',
            '알람': '알람 이력 상세는 장비 상세 화면에서 확인할 수 있습니다.',
            '정비': '정비 일정 및 이력 상세는 장비 상세 화면에서 확인할 수 있습니다.',
            '이력': '자산 변경·인수 이력 상세는 장비 상세 화면에서 확인할 수 있습니다.',
            '문서': '장비 문서(도면·매뉴얼·보증서)는 장비 상세 화면에서 확인할 수 있습니다.'
        };
        return msgs[this.activeSubTab] || '';
    }

    get subTabs() {
        const tabs = ['개요', '성능', '알람', '정비', '이력', '문서'];
        return tabs.map(t => ({ label: t, cls: t === this.activeSubTab ? 'stab on' : 'stab' }));
    }

    // Handlers
    handleSelectAsset(event) {
        this.selectedId = event.currentTarget.dataset.id;
        this.activeSubTab = '개요';
        this.loadSelectedDetail();
    }
    handlePrevPage() { if (this.currentPage > 1) this.currentPage--; }
    handleNextPage() { if (this.currentPage < this.totalPages) this.currentPage++; }
    handlePage(event) { this.currentPage = parseInt(event.currentTarget.dataset.num, 10); }
    handleSearch(event) {
        this.searchTerm = event.target.value;
        this.currentPage = 1;
    }
    handleSubTab(event) { this.activeSubTab = event.currentTarget.dataset.tab; }

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

    renderedCallback() {
        const trendEl = this.template.querySelector('.chart-container');
        if (trendEl && this.isOverview) {
            trendEl.innerHTML = this.trendSvg;
        }
        const donutEl = this.template.querySelector('.donut-container');
        if (donutEl) {
            donutEl.innerHTML = this.donutSvg;
        }
    }
}
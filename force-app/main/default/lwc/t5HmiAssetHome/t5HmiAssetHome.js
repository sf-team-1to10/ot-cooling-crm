import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getAssetHomeData from '@salesforce/apex/T5HmiAssetHomeController.getAssetHomeData';
import acknowledgeAlert from '@salesforce/apex/T5HmiAssetHomeController.acknowledgeAlert';

/**
 * 'YYYY-MM-DD' 날짜 문자열을 오늘 기준 D-day 표기로 바꾼다.
 * 오늘=D-Day, 미래=D-n, 지난 날짜=D+n(정비 지연). 값이 없으면 '예정 없음'.
 */
function formatDday(dateStr) {
    if (!dateStr) {
        return '예정 없음';
    }
    const target = new Date(`${dateStr}T00:00:00`);
    if (Number.isNaN(target.getTime())) {
        return '예정 없음';
    }
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const diffDays = Math.round((target.getTime() - today.getTime()) / 86400000);
    if (diffDays === 0) {
        return 'D-Day';
    }
    return diffDays > 0 ? `D-${diffDays}` : `D+${Math.abs(diffDays)}`;
}

/**
 * "고객 운영 콘솔" — 고객운영홈_HMI.html을 1:1로 이식한 LWC(2026-08-30).
 *
 * 원본은 정적 데모 HTML(하드코딩 ASSETS 배열 + DOM 직접 조작)이라, 데이터는
 * Apex(T5HmiAssetHomeController)로 교체하고 상호작용은 LWC의 반응형
 * getter/이벤트 핸들러로 재작성했다 — 레이아웃·CSS·상호작용 동작 자체는
 * 원본과 동일하게 유지한다(칩 필터는 원본 CSS/JS엔 있지만 실제 마크업이
 * 없는 죽은 코드라 그대로 포팅하지 않음).
 *
 * ⚠ 데모 데이터 경계: 계측값·알람 우선순위 등은 Customer_Alert__c(고객 노출용
 * 경보 레코드)에 사람이 입력해둔 값이다. 실제 구현은 BMS/IoT·SCADA/CMMS가
 * 담당(요구사항 18) — 이 컴포넌트는 그 자리를 Salesforce 데이터로 대체한
 * 데모/파일럿 단계 화면이다.
 */
export default class T5HmiAssetHome extends NavigationMixin(LightningElement) {
    // ---- Apex data ----
    // 초기값을 비워두면 wire가 응답하기 전 첫 렌더링에서 템플릿이
    // {homeData.siteLabel} 같은 경로를 그대로 읽다가 undefined 참조로
    // 터진다(2026-08-30 확인, Experience Builder에서 "Cannot read
    // properties of undefined" 에러로 재현) — 항상 안전한 기본 구조를 준다.
    homeData = {
        siteLabel: '',
        lastUpdatedText: '',
        totalCount: 0,
        normalCount: 0,
        advisoryCount: 0,
        maintenanceCount: 0,
        offlineCount: 0,
        serviceCount: 0,
        assets: [],
        activeAlert: null
    };
    wiredHomeResult;
    isLoading = true;
    loadError;

    // ---- Toolbar / filter state ----
    searchQuery = '';
    typeFilter = '전체 유형';
    statusFilter = '전체 상태';
    sortBy = 'id';
    view = 'card'; // 'card' | 'list'
    selectedId;
    kpiFilter = ''; // KPI 칩 토글 상태 (빈 문자열 = 전체)

    // ---- Drawer / modal ----
    isDrawerOpen = false;
    isModalOpen = false;
    serviceModalAssetLabel = '';

    // ---- Toast (원본의 하단 토스트를 그대로 재현 — platformShowToastEvent가
    //      아니라 원본 CSS의 커스텀 토스트를 씀, 화면 톤을 그대로 유지하기 위해) ----
    toastMessage = '';
    toastVisible = false;
    toastTimer;

    // ---- Carousel scroll ----
    // 'init' = 최초 로드(애니메이션 없이 즉시), 'smooth' = prev/next·카드 클릭.
    _pendingScrollToSelected = false;
    _scrollBehavior = 'auto';

    @wire(getAssetHomeData)
    wiredHome(result) {
        this.wiredHomeResult = result;
        const { data, error } = result;
        if (data) {
            this.homeData = data;
            this.loadError = undefined;
            this.isLoading = false;
            if (!this.selectedId && data.assets && data.assets.length) {
                const advisoryFirst = data.assets.find((a) => a.health === 'Advisory');
                this.selectedId = advisoryFirst ? advisoryFirst.assetId : data.assets[0].assetId;
                // 최초 로드 — 애니메이션 없이 바로 중앙에 위치시킨다(2026-08-30
                // 수정, select()를 거치지 않으므로 여기서 직접 플래그를 켠다).
                this._pendingScrollToSelected = true;
                this._scrollBehavior = 'auto';
            }
        } else if (error) {
            this.loadError = this.reduceError(error);
            this.isLoading = false;
        }
    }

    renderedCallback() {
        if (this._pendingScrollToSelected) {
            this._pendingScrollToSelected = false;
            this.scheduleScrollToCenter(this._scrollBehavior);
        }
    }

    // 선택 카드는 300px→640px로 폭이 트랜지션되는데(.asset-card.selected,
    // CSS transition: width .18s), 그게 끝나기 전에 offsetLeft/offsetWidth를
    // 재면 중앙 계산이 어긋난다(2026-08-30 확인 — 7/16·1/16에서 좌우로
    // 치우쳐 보였던 원인). 최초 로드는 트랜지션 자체가 없으니 rAF 2번으로
    // 레이아웃 확정만 기다리고, 이후 탐색은 transitionend까지 기다린다.
    scheduleScrollToCenter(behavior) {
        const card = this.template.querySelector('.asset-card.selected');
        if (!card) {
            return;
        }

        if (behavior === 'auto') {
            requestAnimationFrame(() => {
                requestAnimationFrame(() => this.scrollSelectedToCenter('auto'));
            });
            return;
        }

        let done = false;
        const finish = () => {
            if (done) return;
            done = true;
            card.removeEventListener('transitionend', onTransitionEnd);
            this.scrollSelectedToCenter(behavior);
        };
        const onTransitionEnd = (event) => {
            if (event.propertyName === 'width') {
                finish();
            }
        };
        card.addEventListener('transitionend', onTransitionEnd);
        // CSS 트랜지션은 180ms — transitionend가 안 오는 예외 상황(이미
        // 같은 폭이라 트랜지션이 안 걸리는 경우 등) 대비 폴백.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(finish, 260);
    }

    // scrollIntoView는 세로 스크롤까지 같이 움직여서 Experience Cloud
    // 페이지 전체가 점프하는 문제가 있었다(2026-08-30 확인) — .track의
    // scrollLeft만 직접 계산해서 가로 스크롤만 움직인다.
    scrollSelectedToCenter(behavior) {
        const track = this.template.querySelector('.track');
        const card = this.template.querySelector('.asset-card.selected');
        if (!track || !card) {
            return;
        }
        const target = card.offsetLeft - (track.clientWidth - card.offsetWidth) / 2;
        if (typeof track.scrollTo === 'function') {
            track.scrollTo({ left: target, behavior });
        } else {
            track.scrollLeft = target;
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Derived data
    // ─────────────────────────────────────────────────────────────────

    get rawAssets() {
        return this.homeData?.assets || [];
    }

    get hasAdvisory() {
        return (this.homeData?.advisoryCount || 0) > 0;
    }

    get availableCount() {
        return (this.homeData?.totalCount || 0) - (this.homeData?.maintenanceCount || 0) - (this.homeData?.offlineCount || 0);
    }

    get meterSegments() {
        const total = this.homeData?.totalCount || 0;
        const segments = [];
        const assets = this.rawAssets;
        for (let i = 0; i < total; i++) {
            const a = assets[i];
            const isAdv = a && a.health === 'Advisory';
            segments.push({
                key: `seg-${i}`,
                cls: isAdv ? 'adv' : ''
            });
        }
        return segments;
    }

    get nextMaintenanceDateGlobal() {
        const assets = this.rawAssets;
        if (!assets.length) return '—';
        let earliest = null;
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        for (const a of assets) {
            if (!a.nextMaintenance) continue;
            const d = new Date(`${a.nextMaintenance}T00:00:00`);
            if (d >= today && (!earliest || d < earliest)) {
                earliest = d;
            }
        }
        return earliest ? earliest.toISOString().slice(0, 10) : '—';
    }

    // KPI 칩 동적 클래스 (선택 시 .on 토글)
    get kpiNormalClass() {
        return `so-kpi${this.kpiFilter === '정상' ? ' on' : ''}`;
    }

    get kpiAdvisoryClass() {
        return `so-kpi${this.kpiFilter === '주의' ? ' on' : ''}`;
    }

    get kpiMaintenanceClass() {
        return `so-kpi mut${this.kpiFilter === '점검 중' ? ' on' : ''}`;
    }

    get kpiServiceClass() {
        return `so-kpi mut${this.kpiFilter === '서비스 진행 중' ? ' on' : ''}`;
    }

    get kpiNormalNumClass() {
        return this.homeData?.normalCount > 0 ? 'k-num ok' : 'k-num';
    }

    get kpiAdvisoryNumClass() {
        return this.homeData?.advisoryCount > 0 ? 'k-num adv' : 'k-num';
    }

    get hasActiveAlert() {
        return !!this.homeData?.activeAlert;
    }

    get activeAlert() {
        return this.homeData?.activeAlert;
    }

    // 모달의 "관련 경보" 필드는 activeAlert가 null일 때(경보 없음/로딩 전)도
    // 항상 렌더링되는 자리라 {activeAlert.categoryLabel} 같은 직접 접근이
    // 위험하다 — 안전하게 문자열만 반환하는 별도 getter를 쓴다.
    get activeAlertCategoryLabelSafe() {
        return this.homeData?.activeAlert?.categoryLabel || '';
    }

    get activeAlertCount() {
        return this.hasActiveAlert ? 1 : 0;
    }

    get isAlertAcknowledged() {
        return !!this.activeAlert?.acknowledged;
    }

    get ackButtonLabel() {
        return this.isAlertAcknowledged ? '확인됨' : '알람 확인';
    }

    get lifecycleLabel() {
        if (!this.hasActiveAlert) return '';
        return this.isAlertAcknowledged ? 'Active · Acknowledged' : 'Active · Unacknowledged';
    }

    get alertDurationText() {
        if (!this.hasActiveAlert || !this.activeAlert.startedAt) return '';
        const started = new Date(this.activeAlert.startedAt);
        const now = new Date();
        const minutes = Math.max(0, Math.round((now - started) / 60000));
        return `${minutes}분`;
    }

    get alertStartTimeText() {
        if (!this.hasActiveAlert || !this.activeAlert.startedAt) return '';
        const started = new Date(this.activeAlert.startedAt);
        return started.toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit', hour12: false });
    }

    get alertMarkerStyle() {
        const a = this.activeAlert;
        if (!a || a.currentValue === null || a.currentValue === undefined || !a.envelopeMin || !a.envelopeMax) {
            return 'left:calc(0% + 2px)';
        }
        // 막대는 [min의 80% ~ max의 120%] 범위를 0~100%로 매핑(원본 디자인의
        // "낮음 | 정상 | 높음" 3구간 느낌을 실제 숫자로 재현).
        const lo = a.envelopeMin * 0.8;
        const hi = a.envelopeMax * 1.2;
        const pct = Math.min(100, Math.max(0, ((a.currentValue - lo) / (hi - lo)) * 100));
        return `left:calc(${pct.toFixed(1)}% - 1px)`;
    }

    get typeOptions() {
        return ['전체 유형', '냉각수 분배 장치', '액체-액체 CDU', '액체-공기 CDU', '냉각 모듈 확장형'];
    }

    get statusOptions() {
        return ['전체 상태', '정상', '주의', '점검 중', '서비스 진행 중'];
    }

    get sortOptions() {
        return [
            { value: 'id', label: 'Asset ID순' },
            { value: 'advisory', label: '주의 상태 우선' },
            { value: 'loc', label: '설치 위치순' },
            { value: 'next', label: '다음 점검일순' }
        ];
    }

    /** 원본 visibleAssets()와 동일한 필터·검색·정렬 순서. */
    get visibleAssets() {
        let list = this.rawAssets.slice();

        // KPI 칩 필터 (toolbar 상태 필터보다 우선)
        if (this.kpiFilter === '정상') {
            list = list.filter((a) => a.health !== 'Advisory' && a.op === 'Normal');
        } else if (this.kpiFilter === '주의') {
            list = list.filter((a) => a.health === 'Advisory');
        } else if (this.kpiFilter === '점검 중') {
            list = list.filter((a) => a.op === 'Maintenance');
        } else if (this.kpiFilter === '서비스 진행 중') {
            list = list.filter((a) => a.serviceInProgress === true);
        } else if (this.statusFilter === '정상') {
            list = list.filter((a) => a.health !== 'Advisory' && a.op === 'Normal');
        } else if (this.statusFilter === '주의') {
            list = list.filter((a) => a.health === 'Advisory');
        } else if (this.statusFilter === '점검 중') {
            list = list.filter((a) => a.op === 'Maintenance');
        } else if (this.statusFilter === '서비스 진행 중') {
            list = list.filter((a) => a.serviceInProgress === true);
        }

        if (this.typeFilter === '냉각수 분배 장치') {
            list = list.filter((a) => a.family === 'CDU');
        } else if (this.typeFilter === '냉각 모듈 확장형') {
            list = list.filter((a) => a.family === 'Module' || a.family === 'MODULE');
        } else if (this.typeFilter === '액체-액체 CDU' || this.typeFilter === '액체-공기 CDU') {
            list = list.filter((a) => a.cat === this.typeFilter);
        }

        if (this.searchQuery) {
            const q = this.searchQuery.trim().toLowerCase();
            list = list.filter((a) =>
                `${a.name} ${a.type} ${a.cat} ${a.loc}`.toLowerCase().includes(q)
            );
        }

        const byId = (a, b) => a.name.localeCompare(b.name, undefined, { numeric: true });
        if (this.sortBy === 'advisory') {
            list.sort((a, b) => (a.health === 'Advisory' ? 0 : 1) - (b.health === 'Advisory' ? 0 : 1) || byId(a, b));
        } else if (this.sortBy === 'loc') {
            list.sort((a, b) => (a.loc || '').localeCompare(b.loc || '', 'ko') || byId(a, b));
        } else if (this.sortBy === 'next') {
            list.sort((a, b) => (a.nextMaintenance || '').localeCompare(b.nextMaintenance || '') || byId(a, b));
        } else {
            list.sort(byId);
        }

        return list;
    }

    /** 카드/리스트 렌더링용으로 서식·클래스까지 미리 계산한 뷰모델. */
    get decoratedAssets() {
        const list = this.visibleAssets;
        return list.map((a) => {
            const advisory = a.health === 'Advisory';
            const selected = a.assetId === this.selectedId;
            return {
                ...a,
                advisory,
                selected,
                cardClass: `asset-card${selected ? ' selected' : ''}${advisory ? ' advisory' : ''}`,
                dotClass: `pg-dot${selected ? ' on' : ''}${advisory ? ' adv' : ''}`,
                lvRowClass: `lv-row${advisory ? ' adv' : ''}`,
                indClass: advisory ? 'ind advisory' : 'ind normal',
                indText: advisory ? 'P3 · 주의' : '정상',
                indTextShort: advisory ? '주의' : '정상',
                lastMaintenanceText: a.lastMaintenance || '기록 없음',
                nextMaintenanceText: formatDday(a.nextMaintenance),
                hasImage: !!a.imageUrl
            };
        });
    }

    get selectedIndex() {
        return this.visibleAssets.findIndex((a) => a.assetId === this.selectedId);
    }

    get posNow() {
        const i = this.selectedIndex;
        return i >= 0 ? i + 1 : 0;
    }

    get posTotal() {
        return this.visibleAssets.length;
    }

    get isPrevDisabled() {
        return this.selectedIndex <= 0;
    }

    get isNextDisabled() {
        const i = this.selectedIndex;
        return i < 0 || i >= this.visibleAssets.length - 1;
    }

    get hasVisibleAssets() {
        return this.visibleAssets.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.loadError && !this.hasVisibleAssets;
    }

    get scrimClass() {
        return this.isDrawerOpen || this.isModalOpen ? 'scrim open' : 'scrim';
    }

    get drawerClass() {
        return this.isDrawerOpen ? 'drawer open' : 'drawer';
    }

    get modalClass() {
        return this.isModalOpen ? 'modal open' : 'modal';
    }

    get isCardView() {
        return this.view === 'card';
    }

    get isListView() {
        return this.view === 'list';
    }

    get viewCardPressed() {
        return String(this.isCardView);
    }

    get viewListPressed() {
        return String(this.isListView);
    }

    // ─────────────────────────────────────────────────────────────────
    // Toolbar handlers
    // ─────────────────────────────────────────────────────────────────

    handleKpiClick(event) {
        const kpi = event.currentTarget.dataset.kpi;
        this.kpiFilter = this.kpiFilter === kpi ? '' : kpi;
        this.reconcileSelection();
    }

    handleSearchInput(event) {
        this.searchQuery = event.target.value;
        this.reconcileSelection();
    }

    handleTypeChange(event) {
        this.typeFilter = event.target.value;
        this.reconcileSelection();
    }

    handleStatusChange(event) {
        this.statusFilter = event.target.value;
        this.reconcileSelection();
    }

    handleSortChange(event) {
        this.sortBy = event.target.value;
    }

    handleViewCard() {
        this.view = 'card';
    }

    handleViewList() {
        this.view = 'list';
    }

    // ─────────────────────────────────────────────────────────────────
    // Carousel
    // ─────────────────────────────────────────────────────────────────

    handlePrev() {
        this.step(-1);
    }

    handleNext() {
        this.step(1);
    }

    step(dir) {
        const list = this.visibleAssets;
        const i = list.findIndex((a) => a.assetId === this.selectedId);
        if (i + dir >= 0 && i + dir < list.length) {
            this.select(list[i + dir].assetId);
        }
    }

    select(id) {
        if (!id || id === this.selectedId) return;
        this.selectedId = id;
        this._pendingScrollToSelected = true;
        this._scrollBehavior = 'smooth';
    }

    reconcileSelection() {
        const list = this.visibleAssets;
        if (!list.find((a) => a.assetId === this.selectedId)) {
            this.selectedId = list.length ? list[0].assetId : undefined;
        }
    }

    handleCardClick(event) {
        if (event.target.closest('[data-action]')) return; // 버튼 클릭은 별도 핸들러가 처리
        const id = event.currentTarget.dataset.id;
        this.select(id);
    }

    handleCardKeydown(event) {
        if (event.key === 'ArrowLeft') {
            event.preventDefault();
            this.step(-1);
        } else if (event.key === 'ArrowRight') {
            event.preventDefault();
            this.step(1);
        } else if (event.key === 'Enter' || event.key === ' ') {
            const id = event.currentTarget.dataset.id;
            if (id !== this.selectedId) {
                event.preventDefault();
                this.select(id);
            }
        }
    }

    handleDotClick(event) {
        this.select(event.currentTarget.dataset.id);
    }

    handleListRowClick(event) {
        if (event.target.closest('button')) return;
        this.select(event.currentTarget.dataset.id);
    }

    _touchStartX = null;

    handleTouchStart(event) {
        this._touchStartX = event.touches[0].clientX;
    }

    handleTouchEnd(event) {
        if (this._touchStartX === null) return;
        const dx = event.changedTouches[0].clientX - this._touchStartX;
        if (Math.abs(dx) > 55) {
            this.step(dx < 0 ? 1 : -1);
        }
        this._touchStartX = null;
    }

    // ─────────────────────────────────────────────────────────────────
    // Detail navigation (요구사항 10 — NavigationMixin으로 실제 Asset 레코드 페이지 이동)
    // ─────────────────────────────────────────────────────────────────

    handleDetailClick(event) {
        const id = event.currentTarget.dataset.id || this.selectedId || this.activeAlert?.assetId;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: `${window.location.pathname.replace(/\/[^/]*$/, '')}/asset-detail?assetId=${id}`
            }
        });
    }

    // ─────────────────────────────────────────────────────────────────
    // Alarm drawer / service modal
    // ─────────────────────────────────────────────────────────────────

    handleOpenDrawer() {
        if (this.activeAlert?.assetId) {
            this.select(this.activeAlert.assetId);
        }
        this.isDrawerOpen = true;
        this.isModalOpen = false;
    }

    handleCloseAll() {
        this.isDrawerOpen = false;
        this.isModalOpen = false;
    }

    handleOpenService(event) {
        const id = event.currentTarget?.dataset?.id || this.selectedId;
        const asset = this.rawAssets.find((a) => a.assetId === id) || this.rawAssets.find((a) => a.assetId === this.selectedId);
        if (asset) {
            this.select(asset.assetId);
            this.serviceModalAssetLabel = `${asset.name} · ${asset.loc || ''}`;
        } else {
            this.serviceModalAssetLabel = '';
        }
        this.isDrawerOpen = false;
        this.isModalOpen = true;
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.handleCloseAll();
        }
    }

    // 원본 데모도 실제로는 Case를 만들지 않고 토스트만 띄운다(주석: "데모에서는
    // 실제 생성되지 않음") — 요구사항 9(자동 Case/WO 생성 금지)와 11(신고
    // 화면 미비 시 안내 토스트)을 그대로 만족하므로 동일하게 유지한다.
    handleServiceSubmit() {
        this.handleCloseAll();
        this.showToast('데모: 서비스 요청이 접수되었습니다. 상세 신고 화면은 준비 중입니다 — 실제 구현 시 Case가 생성되고 Asset·Work Order와 연계됩니다.');
    }

    // ─────────────────────────────────────────────────────────────────
    // Acknowledge — 실제 Apex 호출로 Customer_Alert__c.Status__c만 변경(요구사항 9)
    // ─────────────────────────────────────────────────────────────────

    async handleAcknowledge() {
        if (!this.hasActiveAlert || this.isAlertAcknowledged) {
            this.showToast('이미 확인(Acknowledged)된 경보입니다.');
            return;
        }
        try {
            await acknowledgeAlert({ alertId: this.activeAlert.alertId });
            await refreshApex(this.wiredHomeResult);
            this.showToast('경보를 확인 처리했습니다. 상태: Active · Acknowledged (경보는 계속 활성 상태입니다).');
        } catch (e) {
            this.showToast(this.reduceError(e));
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Toast
    // ─────────────────────────────────────────────────────────────────

    showToast(msg) {
        this.toastMessage = msg;
        this.toastVisible = true;
        clearTimeout(this.toastTimer);
        this.toastTimer = setTimeout(() => {
            this.toastVisible = false;
        }, 3600);
    }

    get toastClass() {
        return this.toastVisible ? 'toast show' : 'toast';
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || '알 수 없는 오류가 발생했습니다.';
    }
}

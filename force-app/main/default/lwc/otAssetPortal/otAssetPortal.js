import { LightningElement } from 'lwc';

/**
 * SPA 컨테이너 — 헤더 네비게이션과 3개 화면(목록/상세/장애 신고)을 전환한다.
 *
 * 2026-08-30 변경: 원래는 목록 클릭 → 바로 장애 신고 화면이었는데, 목업
 * 검토 결과 "목록 → 상세(게이지) → (선택) 장애 신고"가 맞는 흐름이라
 * 'detail' 상태를 추가했다. 헤더의 "장애 신고" 탭을 직접 클릭한 경우(자산
 * 미선택 상태)는 기존처럼 바로 신고 화면으로 간다 — otReportFault 자체가
 * "어느 장비입니까?"를 1번 스텝으로 물어보게 이미 설계돼 있어서 자산 선택
 * 없이 들어가도 자연스럽다.
 */
export default class OtAssetPortal extends LightningElement {
    selectedAssetId;
    selectedAssetName;
    view = 'list'; // 'list' | 'detail' | 'intake'

    get showList() {
        return this.view === 'list';
    }

    get showDetail() {
        return this.view === 'detail';
    }

    get showReport() {
        return this.view === 'intake';
    }

    get activePage() {
        return this.view === 'intake' ? 'intake' : 'assets';
    }

    handleContact(event) {
        this.selectedAssetId = event.detail.assetId;
        this.selectedAssetName = event.detail.assetName;
        this.view = 'detail';
    }

    handleOpenReport() {
        this.view = 'intake';
    }

    handleBackToList() {
        this.view = 'list';
        this.selectedAssetId = undefined;
        this.selectedAssetName = undefined;
    }

    // 장애 신고 화면에서 뒤로가기 — 자산이 선택돼 있었으면 그 자산 상세로,
    // 헤더에서 바로 들어온 경우(자산 미선택)면 목록으로.
    handleBackFromReport() {
        this.view = this.selectedAssetId ? 'detail' : 'list';
    }

    // Header nav: '내 자산' returns to the list; '장애 신고' opens the report
    // screen directly (자산 선택 없이 진입, otReportFault 1번 스텝에서 고름).
    handleNavigate(event) {
        if (event.detail === 'assets') {
            this.handleBackToList();
        } else if (event.detail === 'intake') {
            this.view = 'intake';
        }
    }
}

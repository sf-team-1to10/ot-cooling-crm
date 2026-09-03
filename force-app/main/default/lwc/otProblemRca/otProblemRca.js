import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon
} from 'lightning/platformWorkspaceApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRca from '@salesforce/apex/T5ProblemRcaController.getRca';
import approveActionPlan from '@salesforce/apex/T5ProblemRcaController.approveActionPlan';

export default class OtProblemRca extends LightningElement {
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        this._stateRecordId =
            pageRef?.state?.c__recordId || pageRef?.attributes?.recordId || undefined;
    }

    get effectiveRecordId() {
        return this.recordId || this._stateRecordId || undefined;
    }

    @wire(EnclosingTabId)
    setTabId(tabId) {
        this._tabId = tabId;
        this.labelEnclosingTab();
    }

    async labelEnclosingTab() {
        if (this._tabLabeled || !this._tabId || !this.caseNumber) return;
        this._tabLabeled = true;
        try {
            await setTabLabel(this._tabId, `원인 분석 · Case ${this.caseNumber}`);
            await setTabIcon(this._tabId, 'standard:problem');
        } catch (e) { /* 콘솔 외 컨텍스트 무시 */ }
    }

    rca;
    error;
    _wiredRca;
    approving = false;
    // 데모 반복을 위해 승인 상태는 로컬 클릭 상태로 관리한다.
    // org에 이미 WO가 있어도 페이지 리로드 시 "승인 대기"로 리셋되어 승인 버튼을 다시 누를 수 있다.
    approvedLocally = false;

    @wire(getRca, { caseId: '$effectiveRecordId' })
    wiredRca(result) {
        this._wiredRca = result;
        const { data, error } = result;
        if (data) {
            this.rca = data;
            this.error = undefined;
            this.labelEnclosingTab();
        } else if (error) {
            this.error = error;
            this.rca = undefined;
        }
    }

    get isLoading() {
        return !this.rca && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || 'RCA 데이터를 불러오지 못했습니다.';
    }

    get problemNumber() {
        return this.rca?.problemNumber || '';
    }

    get caseNumber() {
        return this.rca?.caseNumber || '';
    }

    get directCause() {
        return this.rca?.directCause || '—';
    }

    get rootCause() {
        return this.rca?.rootCause || '—';
    }

    get correctiveCount() {
        return this.rca?.correctiveCount ?? 0;
    }

    get preventiveCount() {
        return this.rca?.preventiveCount ?? 0;
    }

    // ─── 현장 근거 (F-07 시운전·복구 측정) ───
    get evidenceFailValue() {
        return this.rca?.evidence?.recoveryFail ?? '—';
    }

    get evidencePassValue() {
        return this.rca?.evidence?.recoveryPass ?? '—';
    }

    get commissionFailValue() {
        return this.rca?.evidence?.commissionFail ?? '—';
    }

    get commissionPassValue() {
        return this.rca?.evidence?.commissionPass ?? '—';
    }

    get evidenceSummary() {
        const fail = this.rca?.evidence?.recoveryFail;
        const pass = this.rca?.evidence?.recoveryPass;
        if (fail != null && pass != null) {
            return `F-07 · ${fail} → ${pass} N·m`;
        }
        return '—';
    }

    // ─── RCA 승인 상태 ───
    // 세션 내 로컬 클릭 상태. 페이지 리로드 시 항상 "승인 대기"로 시작한다.
    get isApproved() {
        return this.approvedLocally;
    }

    get approvalStatus() {
        return this.isApproved ? '승인 완료' : '승인 대기';
    }

    get approvalStatusClass() {
        return this.isApproved ? 'chip chip--pos' : 'chip chip--warn';
    }

    get approvalOwnerLabel() {
        return '서정비 · 서비스 관리자';
    }

    get approveButtonLabel() {
        if (this.approving) return '승인 처리 중...';
        return this.isApproved ? '승인 완료됨' : '시정·예방 계획 승인';
    }

    get approveButtonDisabled() {
        return this.approving;
    }

    // ─── 시정·예방 계획 승인 액션 ───
    // 승인만 조용히 처리하고 상태를 화면에 반영. 사용자는 상단 [시정·예방] 탭을 클릭해 결과를 확인.
    async handleApprove() {
        if (this.approving || this.isApproved) return;
        this.approving = true;
        try {
            const res = await approveActionPlan({ recordId: this.effectiveRecordId });
            await refreshApex(this._wiredRca);
            this.approvedLocally = true;
            const message = res?.alreadyApproved
                ? `이미 생성된 조치 ${res.totalCount}건이 있습니다. [시정·예방] 탭에서 확인하세요.`
                : `시정 ${res.correctiveCount}건 · 예방 ${res.preventiveCount}건 총 ${res.totalCount}건이 생성됐습니다. [시정·예방] 탭에서 확인하세요.`;
            this.dispatchEvent(new ShowToastEvent({
                title: '시정·예방 계획 승인 완료',
                message,
                variant: 'success'
            }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: '승인 실패',
                message: e?.body?.message || e?.message || '승인 처리 중 오류가 발생했습니다.',
                variant: 'error'
            }));
        } finally {
            this.approving = false;
        }
    }
}

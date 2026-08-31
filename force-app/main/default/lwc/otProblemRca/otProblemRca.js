import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon,
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    focusTab
} from 'lightning/platformWorkspaceApi';
import getRca from '@salesforce/apex/T5ProblemRcaController.getRca';

export default class OtProblemRca extends NavigationMixin(LightningElement) {
    // Record page에서는 자동 주입, App Page에서는 pageReference state에서 해석한다.
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        const stateId = pageRef?.state?.c__recordId || pageRef?.attributes?.recordId;
        if (stateId) {
            this._stateRecordId = stateId;
        }
    }

    @wire(IsConsoleNavigation) isConsoleNavigation;

    get isConsole() {
        return this.isConsoleNavigation?.data === true;
    }

    rca;
    error;

    @wire(getRca, { caseId: '$effectiveRecordId' })
    wiredRca({ data, error }) {
        if (data) {
            this.rca = data;
            this.error = undefined;
            this.labelEnclosingTab();
        } else if (error) {
            this.error = error;
            this.rca = undefined;
        }
    }

    @wire(EnclosingTabId)
    setTabId(tabId) {
        this._tabId = tabId;
        this.labelEnclosingTab();
    }

    async labelEnclosingTab() {
        if (this._tabLabeled || !this._tabId || !this.problemNumber) {
            return;
        }
        this._tabLabeled = true;
        await setTabLabel(this._tabId, `${this.problemNumber} RCA`);
        await setTabIcon(this._tabId, 'standard:problem');
    }

    get effectiveRecordId() {
        // undefined를 반환해야 wire가 실행되지 않는다(null이면 Apex가 예외).
        return this.recordId || this._stateRecordId || undefined;
    }

    get isLoading() {
        return !this.rca && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || 'RCA 데이터를 불러오지 못했습니다.';
    }

    get problemNumber() {
        return this.rca?.problemNumber;
    }

    get caseNumberText() {
        return this.rca?.caseNumber || '—';
    }

    get subject() {
        return this.rca?.subject || '—';
    }

    get directCause() {
        return this.rca?.directCause || '—';
    }

    get rootCause() {
        return this.rca?.rootCause || '—';
    }

    get correctiveText() {
        return `시정조치 ${this.rca?.correctiveCount ?? 0}건`;
    }

    get preventiveText() {
        return `예방확인 ${this.rca?.preventiveCount ?? 0}건`;
    }

    // 영향 범위 승인 → step19(조치 생성 결과) 화면을 서브탭으로 연다.
    // evidence·브리핑과 동일하게 UrlAddressable 컴포넌트로 열어 App Page 껍데기 없이 화면만 띄운다.
    async handleApproveScope() {
        const caseId = this.effectiveRecordId;
        if (!caseId) {
            return;
        }
        const pageReference = {
            type: 'standard__component',
            attributes: { componentName: 'c__otActionResults' },
            state: { c__recordId: caseId }
        };

        if (this.isConsole) {
            const focused = await getFocusedTabInfo();
            const subtabId = await openSubtab({
                parentTabId: focused.parentTabId || focused.tabId,
                pageReference,
                focus: true
            });
            await focusTab(subtabId);
        } else {
            this[NavigationMixin.Navigate](pageReference);
        }
    }
}

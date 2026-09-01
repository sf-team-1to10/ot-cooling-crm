import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {
    EnclosingTabId,
    setTabLabel,
    setTabIcon,
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    focusTab
} from 'lightning/platformWorkspaceApi';

export default class OtDispatchCandidates extends NavigationMixin(LightningElement) {
    @api recordId;
    _stateRecordId;
    _tabId;
    _tabLabeled = false;

    isAssigned = false;
    showSwarmFlow = false;
    swarmFlowLoaded = false;

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        this._stateRecordId =
            pageRef?.state?.c__recordId || pageRef?.attributes?.recordId || undefined;
    }

    get effectiveRecordId() {
        return this.recordId || this._stateRecordId || undefined;
    }

    @wire(IsConsoleNavigation) isConsoleNavigation;

    get isConsole() {
        return this.isConsoleNavigation?.data === true;
    }

    // standard__component 서브탭은 로드 완료 시 라벨을 'Loading...'으로 덮으므로,
    // EnclosingTabId wire(=로드 후)로 tabId를 받아 라벨/아이콘을 다시 설정한다.
    @wire(EnclosingTabId)
    setTabId(tabId) {
        this._tabId = tabId;
        this.labelEnclosingTab();
    }

    async labelEnclosingTab() {
        if (this._tabLabeled || !this._tabId) {
            return;
        }
        this._tabLabeled = true;
        await setTabLabel(this._tabId, '담당자 확정');
        await setTabIcon(this._tabId, 'standard:service_resource');
    }

    // 1순위 후보 카드 — 확정 시 picked 상태로 전환
    get cand1Class() {
        return this.isAssigned ? 'cand-item picked' : 'cand-item top';
    }

    // 강시공 확정 — 사람이 선택한다. 확정과 동시에 표준 Swarming Flow를 띄워
    // 이 Case의 Slack 협업 채널을 개설한다. 채널이 붙으면(CollaborationUrl)
    // T5_Swarm_Created_Invite_And_Summary 가 초대와 Case 요약 발신을 이어받는다.
    handleAssign() {
        this.isAssigned = true;
        this.swarmFlowLoaded = false;
        this.showSwarmFlow = true;
    }

    get swarmFlowInputVariables() {
        return [{ name: 'recordId', type: 'String', value: this.effectiveRecordId }];
    }

    get swarmFlowLoading() {
        return !this.swarmFlowLoaded;
    }

    get swarmCardClass() {
        return this.swarmFlowLoaded ? 'swarm-card' : 'swarm-card swarm-card_hidden';
    }

    closeSwarmFlow() {
        this.showSwarmFlow = false;
        this.swarmFlowLoaded = false;
    }

    handleSwarmOverlayClick() {
        this.closeSwarmFlow();
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    handleSwarmStatusChange(event) {
        const status = event.detail.status;
        if (status !== 'ERROR') {
            this.swarmFlowLoaded = true;
        }
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            this.closeSwarmFlow();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: '협업 채널 개설',
                    message:
                        'Slack 채널이 열렸습니다. Case 담당자와 현장 담당자를 초대하고 Case 요약을 발신합니다.',
                    variant: 'success'
                })
            );
        }
    }

    // 서브탭 클릭 → 다른 장면으로 이동.
    async handleSubtab(event) {
        const target = event.currentTarget.dataset.goto;
        const rid = this.effectiveRecordId;
        if (!target || !rid) {
            return;
        }

        if (target === 'case') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: rid, objectApiName: 'Case', actionName: 'view' }
            });
            return;
        }

        const pageReference = {
            type: 'standard__component',
            attributes: { componentName: target },
            state: { c__recordId: rid }
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
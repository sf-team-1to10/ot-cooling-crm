import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    focusTab
} from 'lightning/platformWorkspaceApi';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import CASE_NUMBER from '@salesforce/schema/Case.CaseNumber';

/**
 * Flow screen 컴포넌트. 출동 브리핑 생성 Flow의 마지막 화면에 배치되어,
 * 현재 Case 워크스페이스 주탭 아래에 브리핑 App Page를 서브탭으로 연다.
 * 케이스 → 브리핑 생성 → 브리핑 확인 흐름을 하나의 Case 작업공간에서 이어간다.
 */
export default class OtBriefingNavigator extends NavigationMixin(LightningElement) {
    @api recordId;

    @wire(IsConsoleNavigation) isConsoleNavigation;

    @wire(getRecord, { recordId: '$recordId', fields: [CASE_NUMBER] })
    caseRecord;

    get caseNumber() {
        return getFieldValue(this.caseRecord.data, CASE_NUMBER);
    }

    get isConsole() {
        return this.isConsoleNavigation?.data === true;
    }

    async handleOpen() {
        if (!this.recordId) {
            return;
        }
        // 워크벤치 LWC를 URL-addressable(lightning__UrlAddressable) 컴포넌트로 직접 연다.
        // App Page(navItemPage)로 열면 Lightning이 탭 라벨을 페이지 상단 헤더로 렌더해
        // 워크벤치 자체 헤더와 중복되므로, App Page 껍데기 없이 워크벤치 헤더만 남긴다.
        const pageReference = {
            type: 'standard__component',
            attributes: { componentName: 'c__otDispatchBriefingWorkbench' },
            state: { c__recordId: this.recordId }
        };

        if (this.isConsole) {
            const focused = await getFocusedTabInfo();
            // 탭 라벨/아이콘은 워크벤치 컴포넌트가 EnclosingTabId wire(로드 후)로 설정한다.
            // 여기서 설정하면 컴포넌트 로드 완료 시 'Loading...'으로 덮여 레이스가 난다.
            const subtabId = await openSubtab({
                parentTabId: focused.tabId,
                pageReference,
                focus: true
            });
            await focusTab(subtabId);
        } else {
            this[NavigationMixin.Navigate](pageReference);
        }
    }
}
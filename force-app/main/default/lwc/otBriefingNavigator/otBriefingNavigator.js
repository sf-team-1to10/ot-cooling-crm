import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    focusTab,
    setTabLabel,
    setTabIcon
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
        // navItemPage(App Page 탭) 대신 pageReference를 서브탭에 직접 전달해
        // CustomTab 가시성에 의존하지 않고 연다.
        const pageReference = {
            type: 'standard__navItemPage',
            attributes: { apiName: 'Dispatch_Briefing_Workbench' },
            state: { c__recordId: this.recordId }
        };

        if (this.isConsole) {
            const focused = await getFocusedTabInfo();
            const subtabId = await openSubtab({
                parentTabId: focused.tabId,
                pageReference,
                focus: true
            });
            await setTabLabel(subtabId, '출동 브리핑');
            await setTabIcon(subtabId, 'utility:trending');
            await focusTab(subtabId);
        } else {
            this[NavigationMixin.Navigate](pageReference);
        }
    }
}

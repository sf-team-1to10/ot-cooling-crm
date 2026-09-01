import {
    getFocusedTabInfo,
    getTabInfo,
    openSubtab,
    focusTab
} from 'lightning/platformWorkspaceApi';

export async function openOrFocusSubtab(componentName, recordId) {
    if (!componentName || !recordId) {
        return;
    }

    const focused = await getFocusedTabInfo();
    const parentTabId = focused.parentTabId || focused.tabId;
    const parentInfo = await getTabInfo(parentTabId);
    const subtabIds = (parentInfo?.subtabs || []).map((t) => t.tabId);

    for (const tid of subtabIds) {
        try {
            const info = await getTabInfo(tid);
            if (info?.pageReference?.attributes?.componentName === componentName) {
                await focusTab(tid);
                return;
            }
        } catch (_) {
            // 탭이 닫힌 직후 등 무시
        }
    }

    const pageReference = {
        type: 'standard__component',
        attributes: { componentName },
        state: { c__recordId: recordId }
    };
    const subtabId = await openSubtab({ parentTabId, pageReference, focus: true });
    await focusTab(subtabId);
}

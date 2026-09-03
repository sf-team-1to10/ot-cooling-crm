import { LightningElement, api, wire, track } from 'lwc';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import createCase from '@salesforce/apex/OTCaseIntakeController.createCase';
import getMyAssets from '@salesforce/apex/OTMyAssetsController.getMyAssets';

// Case field API names used by this screen (picklist values are read from the
// org, never hardcoded):
//   Symptom_Category__c  — 증상 분류
//   Impact_Level__c      — 영향 등급
//   Reported_Symptom__c  — 고객 진술 (장문)
import CASE_OBJECT from '@salesforce/schema/Case';
import SYMPTOM_CATEGORY_FIELD from '@salesforce/schema/Case.Symptom_Category__c';
import IMPACT_LEVEL_FIELD from '@salesforce/schema/Case.Impact_Level__c';

export default class OtReportFault extends LightningElement {
    // Selected asset passed from the "내 자산" screen (row-click entry path).
    // When the screen is opened from the header menu these arrive empty and the
    // user picks an asset in step ① instead.
    @api assetId;
    @api assetName;

    // Working selection, so both entry paths behave the same. Seeded from the
    // @api inputs on entry; a fresh component is created each time the portal
    // switches to this screen, so connectedCallback always re-seeds.
    selectedId;

    symptomCategory = '';
    impactLevel = '';
    reportedSymptom = '';

    @track symptomOptions = [];
    @track impactOptions = [];
    @track assets = [];

    isSaving = false;
    error;
    result; // CaseResult returned after save (company / contact / warranty).
    copyButtonLabel = '복사';

    connectedCallback() {
        this.selectedId = this.assetId;
    }

    // Read-only asset list, reused from the "내 자산" controller. No new query
    // or field is introduced — this is the same cacheable read.
    @wire(getMyAssets)
    wiredAssets({ data }) {
        if (data) {
            this.assets = data;
        }
    }

    @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
    caseInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$caseInfo.data.defaultRecordTypeId',
        fieldApiName: SYMPTOM_CATEGORY_FIELD
    })
    wiredSymptom({ data }) {
        if (data) {
            this.symptomOptions = data.values.map((v) => ({
                label: v.label,
                value: v.value
            }));
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$caseInfo.data.defaultRecordTypeId',
        fieldApiName: IMPACT_LEVEL_FIELD
    })
    wiredImpact({ data }) {
        if (data) {
            this.impactOptions = data.values.map((v) => ({
                label: v.label,
                value: v.value
            }));
        }
    }

    get hasResult() {
        return this.result != null;
    }

    // The full asset record for the current selection, so the step ① card looks
    // identical whether the user arrived by row-click or picked here.
    get selectedAsset() {
        if (!this.selectedId) {
            return null;
        }
        return this.assets.find((a) => a.assetId === this.selectedId) || null;
    }

    get hasSelection() {
        return this.selectedId != null;
    }

    get selectedName() {
        const a = this.selectedAsset;
        if (a) {
            return a.name;
        }
        // Fall back to the name passed from the list before assets load.
        return this.assetName;
    }

    get selectedSubline() {
        return this.buildSubline(this.selectedAsset);
    }

    // Assets to choose from in step ①, decorated with a subline.
    get pickList() {
        return this.assets.map((a) => ({
            ...a,
            subline: this.buildSubline(a)
        }));
    }

    get hasPickList() {
        return this.assets.length > 0;
    }

    buildSubline(a) {
        if (!a) {
            return '';
        }
        const parts = [];
        if (a.productName) {
            parts.push(a.productName);
        }
        if (a.serialNumber) {
            parts.push(`S/N ${a.serialNumber}`);
        }
        if (a.status) {
            parts.push(a.status);
        }
        return parts.join(' · ');
    }

    handlePick(event) {
        this.selectedId = event.currentTarget.dataset.id;
    }

    handleChangeAsset() {
        this.selectedId = undefined;
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    get isSubmitDisabled() {
        return (
            this.isSaving ||
            !this.selectedId ||
            !this.symptomCategory ||
            !this.impactLevel ||
            !this.reportedSymptom
        );
    }

    get billableLabel() {
        if (!this.result) {
            return '';
        }
        return this.result.billable ? '유상' : '무상';
    }

    get billableVariant() {
        if (!this.result) return 'neutral';
        return this.result.billable ? 'warning' : 'success';
    }

    get warrantyVariant() {
        if (!this.result?.warrantyDecision) return 'neutral';
        const v = this.result.warrantyDecision;
        if (v === '보증' || v === '보증내') return 'success';
        if (v === '보증외' || v === '비보증') return 'critical';
        return 'info';
    }

    async handleCopyCaseNumber() {
        const num = this.result?.caseNumber;
        if (!num) return;
        try {
            await navigator.clipboard.writeText(num);
            this.copyButtonLabel = '복사됨 ✓';
        } catch (_) {
            this.copyButtonLabel = '복사 실패';
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.copyButtonLabel = '복사';
        }, 2000);
    }

    handleSymptomChange(event) {
        this.symptomCategory = event.detail.value;
    }

    handleImpactChange(event) {
        this.impactLevel = event.detail.value;
    }

    handleStatementChange(event) {
        this.reportedSymptom = event.detail.value;
    }

    async handleSubmit() {
        this.error = undefined;
        this.result = undefined;
        this.isSaving = true;
        try {
            this.result = await createCase({
                request: {
                    assetId: this.selectedId,
                    symptomCategory: this.symptomCategory,
                    impactLevel: this.impactLevel,
                    reportedSymptom: this.reportedSymptom
                }
            });
        } catch (e) {
            this.error = this.reduceError(e);
        } finally {
            this.isSaving = false;
        }
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || '신고 저장 중 오류가 발생했습니다.';
    }
}

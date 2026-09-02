import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getContext from '@salesforce/apex/T5MeasurementController.getContext';
import saveMeasurement from '@salesforce/apex/T5MeasurementController.saveMeasurement';
import completeWork from '@salesforce/apex/T5MeasurementController.completeWork';
import getHistory from '@salesforce/apex/T5MeasurementController.getHistory';

// T5-31 현장 복구 작업 측정 플로우 (T5-33에서 홈 화면 개편).
// 단계: home → knowledge / measure → (측정 완료) → 작업 완료.
// completeWork 는 WorkOrder.Status=Completed 로 바꿔 T5-29 Slack 발신 Flow를 트리거한다.
const STEP_HOME = 'home';
const STEP_KNOWLEDGE = 'knowledge';
const STEP_MEASURE = 'measure';

export default class T5RepairMeasurement extends NavigationMixin(LightningElement) {
    @api recordId;

    step = STEP_HOME;
    lines = [];
    articles = [];
    saving = false;
    completing = false;
    completed = false;

    _wired;

    @wire(getContext, { workOrderId: '$recordId' })
    wiredContext(result) {
        this._wired = result;
        const { data } = result;
        if (!data) {
            return;
        }
        this.articles = data.articles ?? [];
        this.lines = (data.lines ?? []).map(line => this.decorate(line));
    }

    // ─── 화면 상태 게터 ────────────────────────────────────────────
    get isHome() {
        return this.step === STEP_HOME;
    }
    get isKnowledge() {
        return this.step === STEP_KNOWLEDGE;
    }
    get isMeasure() {
        return this.step === STEP_MEASURE;
    }
    get hasArticles() {
        return this.articles.length > 0;
    }
    get hasLines() {
        return this.lines.length > 0;
    }

    get homeSubtitle() {
        return '유사사례를 확인하거나 바로 측정을 시작할 수 있습니다.';
    }

    get statusSummary() {
        if (!this.hasLines) return '';
        const total = this.lines.length;
        const saved = this.lines.filter(l => l.saved).length;
        const pass = this.lines.filter(l => l.saved && l.isPass).length;
        return `${total}개 항목 · 측정 ${saved} · 합격 ${pass}`;
    }

    get footLabel() {
        if (!this.hasLines) return '';
        if (this.allPassed) {
            return `${this.lines.length}개 항목 모두 합격 · 자동 판정 (WOLI_Judgement_AutoSet)`;
        }
        const remain = this.lines.filter(l => !l.saved).length;
        const fail = this.lines.filter(l => l.saved && !l.isPass).length;
        if (fail > 0) return `${fail}개 항목 불합격 · 재시험 필요`;
        return `${remain}개 항목 측정 대기`;
    }

    get footDotClass() {
        if (!this.hasLines) return 'dot dot_idle';
        if (this.allPassed) return 'dot dot_ok';
        const fail = this.lines.some(l => l.saved && !l.isPass);
        return fail ? 'dot dot_fail' : 'dot dot_idle';
    }

    // 모든 측정 항목이 저장되고 전부 합격이어야 작업 완료 버튼이 열린다.
    get allPassed() {
        return this.hasLines && this.lines.every(line => line.saved && line.isPass);
    }
    get completeDisabled() {
        return !this.allPassed || this.completing || this.completed;
    }
    get completeHint() {
        if (this.completed) {
            return '작업이 완료 처리되어 Slack에 보고되었습니다.';
        }
        if (!this.hasLines) {
            return '측정 항목이 없습니다.';
        }
        return this.allPassed
            ? '모든 항목 합격 — 작업을 완료할 수 있습니다.'
            : '모든 측정 항목이 합격해야 작업을 완료할 수 있습니다.';
    }

    // ─── 네비게이션 ───────────────────────────────────────────────
    goKnowledge() {
        this.step = STEP_KNOWLEDGE;
    }
    goMeasure() {
        this.step = STEP_MEASURE;
    }
    goHome() {
        this.step = STEP_HOME;
    }

    openArticle(event) {
        const articleId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: articleId, actionName: 'view' }
        });
    }

    // ─── 측정값 저장 ───────────────────────────────────────────────
    handleInput(event) {
        const lineId = event.currentTarget.dataset.id;
        const raw = event.target.value;
        const line = this.lines.find(l => l.id === lineId);
        if (line) {
            line.draft = raw === '' ? null : Number(raw);
        }
    }

    async handleSave(event) {
        const lineId = event.currentTarget.dataset.id;
        const line = this.lines.find(l => l.id === lineId);
        if (!line || line.draft === null || line.draft === undefined || Number.isNaN(line.draft)) {
            this.toast('입력 확인', '측정값을 입력하세요.', 'warning');
            return;
        }
        this.saving = true;
        try {
            const saved = await saveMeasurement({ lineItemId: lineId, value: line.draft });
            this.lines = this.lines.map(l =>
                l.id === lineId ? this.decorate({ ...saved, saved: true }) : l
            );
            const passed = saved.isPass;
            this.toast(
                passed ? '합격' : '불합격',
                passed ? `${saved.point}: ${saved.measured}${saved.unit ?? ''} — 허용구간 통과`
                       : `${saved.point}: ${saved.measured}${saved.unit ?? ''} — 허용구간 벗어남`,
                passed ? 'success' : 'error'
            );
        } catch (e) {
            this.toast('저장 실패', this.errText(e), 'error');
        } finally {
            this.saving = false;
        }
    }

    // ─── 작업 완료 ────────────────────────────────────────────────
    async handleComplete() {
        if (!this.allPassed) {
            return;
        }
        this.completing = true;
        try {
            await completeWork({ workOrderId: this.recordId });
            this.completed = true;
            this.toast('작업 완료', '작업이 완료 처리되었습니다. Slack에 완료 보고가 전송됩니다.', 'success');
            if (this._wired) {
                await refreshApex(this._wired);
            }
        } catch (e) {
            this.toast('완료 실패', this.errText(e), 'error');
        } finally {
            this.completing = false;
        }
    }

    // ─── 이력 토글 ────────────────────────────────────────────────
    async handleToggleHistory(event) {
        const lineId = event.currentTarget.dataset.id;
        const code = event.currentTarget.dataset.code;
        const target = this.lines.find(l => l.id === lineId);
        if (!target) return;

        if (target.historyOpen) {
            this.lines = this.lines.map(l =>
                l.id === lineId ? { ...l, historyOpen: false, historyToggleLabel: '이력 보기' } : l
            );
            return;
        }

        this.lines = this.lines.map(l =>
            l.id === lineId
                ? { ...l, historyOpen: true, historyLoading: true, historyToggleLabel: '이력 접기' }
                : l
        );

        try {
            const rows = await getHistory({ workOrderId: this.recordId, itemCode: code, maxRows: 8 });
            const decorated = (rows ?? []).map(r => this.decorateHistory(r));
            this.lines = this.lines.map(l =>
                l.id === lineId
                    ? { ...l, historyLoading: false, history: decorated, hasHistory: decorated.length > 0 }
                    : l
            );
        } catch (e) {
            this.toast('이력 로드 실패', this.errText(e), 'error');
            this.lines = this.lines.map(l =>
                l.id === lineId
                    ? { ...l, historyLoading: false, history: [], hasHistory: false }
                    : l
            );
        }
    }

    decorateHistory(row) {
        const pass = row.isPass === true;
        return {
            ...row,
            dateLabel: this.formatDate(row.measuredAt),
            valueClass: pass ? 'hitem__val hitem__val_pass' : 'hitem__val hitem__val_fail',
            badgeClass: pass ? 'hbadge hbadge_pass' : 'hbadge hbadge_fail'
        };
    }

    formatDate(value) {
        if (!value) return '';
        const d = new Date(value);
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return `${y}-${m}-${day}`;
    }

    // ─── 헬퍼 ─────────────────────────────────────────────────────
    decorate(line) {
        const saved = line.saved === true || (line.measured !== null && line.measured !== undefined);
        const pass = line.isPass === true;
        const point = line.point ?? '';
        const code = line.itemCode ?? '';
        const headline = code && code !== point ? `${point} ${code}` : point;
        return {
            ...line,
            itemCode: code,
            headline,
            draft: line.measured ?? null,
            saved,
            isPass: pass,
            rangeLabel: this.rangeLabel(line.thresholdMin, line.thresholdMax, line.unit),
            rangeShort: this.rangeShort(line.thresholdMin, line.thresholdMax, line.unit),
            valueClass: pass ? 'scard__value scard__value_pass' : 'scard__value scard__value_fail',
            badgeClass: saved
                ? (pass ? 'badge badge_pass' : 'badge badge_fail')
                : 'badge badge_idle',
            summaryBadgeClass: saved
                ? (pass ? 'sbadge sbadge_pass' : 'sbadge sbadge_fail')
                : 'sbadge sbadge_idle',
            badgeLabel: saved ? (pass ? '합격' : '불합격') : '미측정',
            retestVisible: saved && pass
                && line.previous !== null && line.previous !== undefined
                && line.retestRound && line.retestRound > 1,
            historyOpen: false,
            historyLoading: false,
            history: [],
            hasHistory: false,
            historyToggleLabel: '이력 보기'
        };
    }

    rangeLabel(min, max, unit) {
        const u = unit ?? '';
        if (min !== null && min !== undefined && max !== null && max !== undefined) {
            return `허용구간 ${min} ~ ${max} ${u}`;
        }
        if (min !== null && min !== undefined) {
            return `허용 하한 ${min} ${u} 이상`;
        }
        if (max !== null && max !== undefined) {
            return `허용 상한 ${max} ${u} 이하`;
        }
        return '허용구간 미설정';
    }

    rangeShort(min, max, unit) {
        const u = unit ?? '';
        if (min !== null && min !== undefined && max !== null && max !== undefined) {
            return `허용 ${min}~${max} ${u}`;
        }
        if (min !== null && min !== undefined) return `허용 ${min} 이상 ${u}`;
        if (max !== null && max !== undefined) return `허용 ${max} 이하 ${u}`;
        return '';
    }

    errText(e) {
        return e?.body?.message ?? e?.message ?? '알 수 없는 오류가 발생했습니다.';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

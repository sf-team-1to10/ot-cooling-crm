import { LightningElement, api } from 'lwc';

/**
 * Reusable single-metric gauge — 산업용 HMI/SCADA 계기판 톤(다크 배경, 반원
 * 다이얼, 색상 구간 밴드, 큰 숫자)으로 렌더링한다(2026-08-30 리디자인 —
 * 원래는 밝은 배경의 얇은 원형 링이었는데, 참고 이미지(EV 충전기 HMI,
 * 병원 모니터, 차량 계기판, LS ELECTRIC 산업용 대시보드)와 톤을 맞춤).
 *
 * 다이얼 밴드(초록/노랑/빨강)는 실제 임계값 데이터가 없어서(WorkOrderLineItem.
 * Threshold_Min__c/Max__c가 이 org엔 비어있음, 2026-08-30 확인) 고정 3등분
 * 구획으로 그린다 — 정밀 계기가 아니라 "상태를 한눈에" 보여주는 목적은 이전
 * 원형 링 버전과 동일(바늘 각도도 status 기반 고정 3단계 매핑을 그대로 씀).
 * 스파크라인 아래의 "관측 범위"는 실제 최근 데이터(sparklineValues)의
 * min/max를 그대로 쓴다 — 공식 스펙 임계값이 아니라 최근 실측 범위라는 점을
 * 명확히 라벨링한다.
 *
 * Used by otTrendAlertCard (T5-07, customer portal — one instance per
 * currently-abnormal measurement item) and intended for reuse by the Asset
 * record page (T5-21, internal). See T5_시각화_실시간알림_구조정리.md.
 */
export default class T5GaugeSvg extends LightningElement {
    /** Human-readable label, e.g. "유량". */
    @api label;

    /** Current measured value (already rounded/formatted by the caller if needed). */
    @api value;

    /** Unit suffix shown next to the value, e.g. "L/min". Optional. */
    @api unit = '';

    /** 정상 | 주의 | 이상 */
    @api status;

    /** Value immediately before this one, for the "직전 대비" mini card. Optional. */
    @api previousValue;

    /** Recent readings, oldest → newest, for the sparkline + 관측 범위. Optional. */
    @api
    get sparklineValues() {
        return this._sparklineValues;
    }
    set sparklineValues(v) {
        this._sparklineValues = Array.isArray(v) ? v : [];
    }
    _sparklineValues = [];

    // ---- Status ----
    get statusText() {
        if (this.status === '이상') return '이상';
        if (this.status === '주의') return '주의';
        return '정상';
    }

    get statusDotClass() {
        if (this.status === '이상') return 'dot bad';
        if (this.status === '주의') return 'dot warn';
        return 'dot ok';
    }

    get statusPillClass() {
        if (this.status === '이상') return 'pill bad';
        if (this.status === '주의') return 'pill warn';
        return 'pill ok';
    }

    // ---- Dial (반원 게이지) ----
    // Fixed 3-tier mapping — "state at a glance", not a calibrated scale.
    get gaugePercent() {
        if (this.status === '이상') return 90;
        if (this.status === '주의') return 55;
        return 15;
    }

    // 0% → 바늘이 왼쪽(-90deg)을 가리킴, 100% → 오른쪽(+90deg), 50% → 정중앙(0deg).
    get needleStyle() {
        const deg = -90 + (this.gaugePercent / 100) * 180;
        return `transform: rotate(${deg}deg);`;
    }

    get displayValue() {
        return this.value === null || this.value === undefined
            ? '—'
            : Number(this.value).toLocaleString('ko-KR');
    }

    // ---- Sparkline + 관측 범위 ----
    static SPARK_WIDTH = 80;
    static SPARK_HEIGHT = 24;

    get hasSparkline() {
        return this._sparklineValues.length >= 2;
    }

    get sparklinePoints() {
        const values = this._sparklineValues;
        if (values.length < 2) {
            return '';
        }
        const w = T5GaugeSvg.SPARK_WIDTH;
        const h = T5GaugeSvg.SPARK_HEIGHT;
        const min = Math.min(...values);
        const max = Math.max(...values);
        const range = max - min || 1; // avoid divide-by-zero when flat
        return values
            .map((v, i) => {
                const x = (i / (values.length - 1)) * w;
                const y = h - ((v - min) / range) * h;
                return `${x.toFixed(1)},${y.toFixed(1)}`;
            })
            .join(' ');
    }

    // 공식 임계값이 아니라 "최근 실측값 중 최소~최대" — 라벨로 명확히 구분해서 보여준다.
    get observedRangeText() {
        if (!this.hasSparkline) {
            return '';
        }
        const values = this._sparklineValues;
        const min = Math.min(...values);
        const max = Math.max(...values);
        return `최근 관측 범위 ${min.toLocaleString('ko-KR')} ~ ${max.toLocaleString('ko-KR')}`;
    }

    // ---- Before/after mini card ----
    get hasDelta() {
        return (
            this.previousValue !== null &&
            this.previousValue !== undefined &&
            this.value !== null &&
            this.value !== undefined
        );
    }

    get deltaValue() {
        if (!this.hasDelta) {
            return 0;
        }
        return this.value - this.previousValue;
    }

    get deltaText() {
        if (!this.hasDelta) {
            return '';
        }
        const diff = this.deltaValue;
        const sign = diff > 0 ? '+' : '';
        return `${this.previousValue.toLocaleString('ko-KR')} → ${this.value.toLocaleString('ko-KR')} (${sign}${diff.toLocaleString('ko-KR')})`;
    }

    get deltaClass() {
        if (!this.hasDelta) {
            return 'delta';
        }
        return this.deltaValue < 0 ? 'delta down' : 'delta up';
    }
}
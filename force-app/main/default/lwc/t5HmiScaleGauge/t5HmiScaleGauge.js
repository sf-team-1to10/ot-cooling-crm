import { LightningElement, api } from 'lwc';

// Arc gauge constants
const GA0 = 200;       // start angle (left-bottom)
const GA1 = -20;       // end angle (right-bottom)
const GSPAN = GA0 - GA1; // 220 total arc

function polar(cx, cy, r, deg) {
    const a = (deg * Math.PI) / 180;
    return [cx + r * Math.cos(a), cy - r * Math.sin(a)];
}

function gArc(cx, cy, r, f0, f1, color, w) {
    const a0 = GA0 - f0 * GSPAN;
    const a1 = GA0 - f1 * GSPAN;
    const p0 = polar(cx, cy, r, a0);
    const p1 = polar(cx, cy, r, a1);
    const large = Math.abs(a1 - a0) > 180 ? 1 : 0;
    return `<path d="M${p0[0].toFixed(1)} ${p0[1].toFixed(1)}A${r} ${r} 0 ${large} 1 ${p1[0].toFixed(1)} ${p1[1].toFixed(1)}" fill="none" stroke="${color}" stroke-width="${w}"/>`;
}

function drawGauge(opt) {
    const cx = 120,
        cy = 122,
        r = 92,
        w = 15,
        rLab = r + w / 2 + 13;
    const frac = (v) =>
        Math.max(0, Math.min(1, (v - opt.min) / (opt.max - opt.min)));
    let s = '';

    // Base track
    s += gArc(cx, cy, r, 0, 1, '#E6EAED', w);

    // Color zones
    let prev = 0;
    (opt.zones || []).forEach((z) => {
        s += gArc(cx, cy, r, prev, z.to, z.color, w);
        prev = z.to;
    });

    // Major/minor ticks + numbers
    const minorsPer = opt.minorPerMajor || 5;
    const total = opt.ticks * minorsPer;
    for (let k = 0; k <= total; k++) {
        const f = k / total;
        const a = GA0 - f * GSPAN;
        const major = k % minorsPer === 0;
        const ri = r - w / 2 - 1;
        const ro = r + w / 2 + (major ? 5 : 2.5);
        const p1 = polar(cx, cy, ri, a);
        const p2 = polar(cx, cy, ro, a);
        s += `<line x1="${p1[0].toFixed(1)}" y1="${p1[1].toFixed(1)}" x2="${p2[0].toFixed(1)}" y2="${p2[1].toFixed(1)}" stroke="${major ? '#6E7E88' : '#AEBAC1'}" stroke-width="${major ? 1.5 : 1}"/>`;
        if (major) {
            const lp = polar(cx, cy, rLab, a);
            const val = Math.round(opt.min + f * (opt.max - opt.min));
            s += `<text x="${lp[0].toFixed(1)}" y="${lp[1].toFixed(1)}" text-anchor="middle" dominant-baseline="central" font-family="ui-monospace,Menlo,Consolas,monospace" font-size="10.5" font-weight="500" style="font-variant-numeric:tabular-nums" fill="#53636D">${val}</text>`;
        }
    }

    // Needle + hub
    const na = GA0 - frac(opt.pv) * GSPAN;
    const np = polar(cx, cy, r - 11, na);
    const tp = polar(cx, cy, 18, na + 180);
    s += `<line x1="${tp[0].toFixed(1)}" y1="${tp[1].toFixed(1)}" x2="${np[0].toFixed(1)}" y2="${np[1].toFixed(1)}" stroke="#1A2530" stroke-width="3.2" stroke-linecap="round"/>`;
    s += `<circle cx="${cx}" cy="${cy}" r="8" fill="#1A2530"/>`;
    s += `<circle cx="${cx}" cy="${cy}" r="3.2" fill="#FFFFFF"/>`;

    return `<svg viewBox="0 0 240 170" xmlns="http://www.w3.org/2000/svg">${s}</svg>`;
}

function drawSparkline(arr, color) {
    const w = 200,
        h = 22,
        n = arr.length;
    const mn = Math.min(...arr),
        mx = Math.max(...arr);
    const rng = mx - mn || 1;
    const pts = arr
        .map(
            (v, i) =>
                `${((i / (n - 1)) * w).toFixed(1)},${(h - 3 - ((v - mn) / rng) * (h - 6)).toFixed(1)}`
        )
        .join(' ');
    const last = pts.split(' ').pop().split(',');
    return (
        `<svg viewBox="0 0 200 22" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">` +
        `<polyline points="${pts}" fill="none" stroke="${color}" stroke-width="1.6" stroke-linejoin="round"/>` +
        `<circle cx="${last[0]}" cy="${last[1]}" r="2" fill="${color}"/>` +
        `</svg>`
    );
}

export default class T5HmiScaleGauge extends LightningElement {
    @api gaugeTitle;
    @api badge;
    @api alertLevel;
    @api value;
    @api unit;
    @api gaugeMin;
    @api gaugeMax;
    @api zones;
    @api ticks;
    @api minorPerMajor;
    @api sparkData;
    @api sparkColor;
    @api sparkLabel;
    @api sparkRef;
    @api explain;
    @api extraNote;

    _rendered = false;
    _lastConfigKey = '';

    get cardClass() {
        return 'gcard ' + (this.alertLevel || 'ok');
    }

    get badgeClass() {
        return 'gc-badge';
    }

    get formattedValue() {
        const v = Number(this.value);
        if (Number.isNaN(v)) {
            return this.value;
        }
        return Number.isInteger(v) ? String(v) : v.toFixed(1);
    }

    get hasSparkData() {
        return Array.isArray(this.sparkData) && this.sparkData.length > 0;
    }

    /** Build a string key from all props that affect rendering. */
    _buildConfigKey() {
        return JSON.stringify([
            this.value,
            this.gaugeMin,
            this.gaugeMax,
            this.zones,
            this.ticks,
            this.minorPerMajor,
            this.sparkData,
            this.sparkColor,
            this.extraNote
        ]);
    }

    renderedCallback() {
        const key = this._buildConfigKey();
        if (this._rendered && key === this._lastConfigKey) {
            return;
        }
        this._rendered = true;
        this._lastConfigKey = key;

        // Render arc gauge
        const gaugeEl = this.template.querySelector('.gauge-container');
        if (gaugeEl) {
            // eslint-disable-next-line @lwc/lwc/no-inner-html
            gaugeEl.innerHTML = drawGauge({
                min: Number(this.gaugeMin) || 0,
                max: Number(this.gaugeMax) || 100,
                pv: Number(this.value) || 0,
                zones: this.zones || [],
                ticks: Number(this.ticks) || 6,
                minorPerMajor: Number(this.minorPerMajor) || 5
            });
        }

        // Render sparkline
        if (this.hasSparkData) {
            const sparkEl = this.template.querySelector('.spark-container');
            if (sparkEl) {
                // eslint-disable-next-line @lwc/lwc/no-inner-html
                sparkEl.innerHTML = drawSparkline(
                    this.sparkData,
                    this.sparkColor || '#D8452F'
                );
            }
        }

        // Render extra note HTML
        if (this.extraNote) {
            const noteEl = this.template.querySelector('.extra-note');
            if (noteEl) {
                // eslint-disable-next-line @lwc/lwc/no-inner-html
                noteEl.innerHTML = this.extraNote;
            }
        }
    }
}

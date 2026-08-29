import { LightningElement, api } from 'lwc';

/**
 * OT전자 상태 뱃지 컴포넌트
 * variant: critical | warning | success | info | neutral
 */
export default class OtStatusBadge extends LightningElement {
    @api label = '';

    /** critical | warning | success | info | neutral */
    @api variant = 'neutral';

    get badgeClass() {
        const variantMap = {
            critical: 'ot-badge ot-badge--critical',
            warning:  'ot-badge ot-badge--warning',
            success:  'ot-badge ot-badge--success',
            info:     'ot-badge ot-badge--info',
            neutral:  'ot-badge ot-badge--neutral'
        };
        return variantMap[this.variant] || variantMap.neutral;
    }
}

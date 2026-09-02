import { LightningElement, api } from 'lwc';

export default class OtEquipStatusChip extends LightningElement {
    @api label = '';
    @api variant = 'neutral'; // 'ok' | 'adv' | 'info' | 'neutral'

    get chipClass() {
        const map = { ok: 'chip ok', adv: 'chip adv', info: 'chip info', neutral: 'chip neutral' };
        return map[this.variant] || 'chip neutral';
    }
}
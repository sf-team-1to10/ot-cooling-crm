import { LightningElement, api } from 'lwc';

export default class OtEquipUtilBar extends LightningElement {
    @api breadcrumbPrefix = '고객 포털';
    @api breadcrumbCurrent = '내 자산';
    @api notificationCount = 3;
    @api userName = '유신';
    @api userRole = '고객 운영 담당자';

    get initial() {
        return this.userName ? this.userName.charAt(0) : '';
    }

    get showBadge() {
        return this.notificationCount > 0;
    }

    handleMenu() {
        this.dispatchEvent(new CustomEvent('menuclick'));
    }
}
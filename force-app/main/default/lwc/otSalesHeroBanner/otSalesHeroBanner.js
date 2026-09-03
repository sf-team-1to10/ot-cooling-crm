import { LightningElement } from 'lwc';
import OT_SALES_HERO from '@salesforce/resourceUrl/OT_Sales_Hero';

export default class OtSalesHeroBanner extends LightningElement {
    get heroImageUrl() {
        return OT_SALES_HERO;
    }
}
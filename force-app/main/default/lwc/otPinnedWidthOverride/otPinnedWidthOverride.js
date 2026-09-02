import { LightningElement } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import pinnedOverride from '@salesforce/resourceUrl/pinnedRegionOverride';

export default class OtPinnedWidthOverride extends LightningElement {
    _loaded = false;

    connectedCallback() {
        if (!this._loaded) {
            this._loaded = true;
            loadStyle(this, pinnedOverride);
        }
    }
}

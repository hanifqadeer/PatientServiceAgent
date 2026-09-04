import { LightningElement, wire } from 'lwc';
import getActivePrograms from '@salesforce/apex/EnrollmentController.getActivePrograms';

/**
 * @description Reusable Care Program picker for enrollment flow.
 *              Loads active programs, supports text search, fires selection event.
 */
export default class CareProgramSelector extends LightningElement {
    programs;
    filteredPrograms;
    selectedProgramId;
    searchTerm = '';

    @wire(getActivePrograms)
    wiredPrograms({ error, data }) {
        if (data) {
            this.programs = data;
            this.filteredPrograms = this._decoratePrograms(data);
        } else if (error) {
            console.error('Error loading programs:', error);
        }
    }

    handleSearch(event) {
        this.searchTerm = event.target.value.toLowerCase();
        const filtered = this.programs.filter(
            (p) =>
                p.Name.toLowerCase().includes(this.searchTerm) ||
                (p.Program_Type__c && p.Program_Type__c.toLowerCase().includes(this.searchTerm)) ||
                (p.Therapy_Area__c && p.Therapy_Area__c.toLowerCase().includes(this.searchTerm)) ||
                (p.Product_Name__c && p.Product_Name__c.toLowerCase().includes(this.searchTerm))
        );
        this.filteredPrograms = this._decoratePrograms(filtered);
    }

    handleProgramSelect(event) {
        this.selectedProgramId = event.currentTarget.dataset.id;
        this.filteredPrograms = this._decoratePrograms(
            this.searchTerm
                ? this.programs.filter((p) => p.Name.toLowerCase().includes(this.searchTerm))
                : this.programs
        );
        const selected = this.programs.find((p) => p.Id === this.selectedProgramId);
        this.dispatchEvent(
            new CustomEvent('programselect', { detail: { program: selected } })
        );
    }

    _decoratePrograms(list) {
        return list.map((p) => ({
            ...p,
            cssClass:
                'slds-box slds-m-bottom_x-small slds-p-around_small program-card' +
                (p.Id === this.selectedProgramId ? ' slds-theme_shade' : '')
        }));
    }
}

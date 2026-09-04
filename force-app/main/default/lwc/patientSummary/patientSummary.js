import { LightningElement, api, track } from 'lwc';
import getPatientSummary from '@salesforce/apex/PatientSummaryController.getPatientSummary';
import getPlanSummary from '@salesforce/apex/PatientSummaryController.getPlanSummary';
import { NavigationMixin } from 'lightning/navigation';

/**
 * @description Patient 360 summary for the Care Coordinator.
 *              Displays patient details, support plans, AI summary,
 *              recent activity, affiliations, and quick actions.
 */
export default class PatientSummary extends NavigationMixin(LightningElement) {
    @api recordId; // Patient Account Id
    @track summaryData;
    @track planSummary;

    isLoading = true;
    error;

    get caseColumns() {
        return [
            { label: 'Case #', fieldName: 'CaseNumber', type: 'text' },
            { label: 'Subject', fieldName: 'Subject', type: 'text' },
            { label: 'Category', fieldName: 'Support_Category__c', type: 'text' },
            { label: 'Status', fieldName: 'Status', type: 'text' },
            { label: 'Priority', fieldName: 'Priority', type: 'text' },
            { label: 'Created', fieldName: 'CreatedDate', type: 'date' }
        ];
    }

    connectedCallback() {
        this._loadSummary();
    }

    async _loadSummary() {
        this.isLoading = true;
        try {
            this.summaryData = await getPatientSummary({ patientId: this.recordId });

            // Load AI summary for the first active plan
            if (this.summaryData.supportPlans && this.summaryData.supportPlans.length > 0) {
                const activePlan = this.summaryData.supportPlans.find(
                    (p) => p.Status !== 'Closed'
                ) || this.summaryData.supportPlans[0];
                this.planSummary = await getPlanSummary({ planId: activePlan.Id });
            }
        } catch (err) {
            this.error = err.body?.message || 'Failed to load patient summary.';
        } finally {
            this.isLoading = false;
        }
    }

    handlePlanClick(event) {
        const planId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: planId, objectApiName: 'Case', actionName: 'view' }
        });
    }

    handleNewCase() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Case', actionName: 'new' }
        });
    }

    handleNewTask() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Task', actionName: 'new' }
        });
    }

    handleLogEvent() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Event', actionName: 'new' }
        });
    }
}

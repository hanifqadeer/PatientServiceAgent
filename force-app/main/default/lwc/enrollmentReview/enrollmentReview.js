import { LightningElement, track } from 'lwc';
import extractFromDocument from '@salesforce/apex/EnrollmentController.extractFromDocument';
import searchDuplicatePatients from '@salesforce/apex/EnrollmentController.searchDuplicatePatients';
import confirmEnrollment from '@salesforce/apex/EnrollmentController.confirmEnrollment';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const STEPS = { UPLOAD: 'upload', REVIEW: 'review', SUCCESS: 'success' };

/**
 * @description Primary custom LWC — the enrollment specialist's workspace.
 *              Upload → AI extraction → human review/edit → duplicate check
 *              → confirm → create Patient + PSP.
 *
 *              Per architecture: "Human-reviewed extraction" (ADR-010).
 */
export default class EnrollmentReview extends LightningElement {
    @track extraction = {};
    @track duplicatePatients = [];
    @track enrollmentResult = {};

    currentStep = STEPS.UPLOAD;
    isLoading = false;
    selectedExistingPatientId = null;
    documentId = null;

    // ── Step visibility ──
    get isUploadStep() { return this.currentStep === STEPS.UPLOAD; }
    get isReviewStep() { return this.currentStep === STEPS.REVIEW; }
    get isSuccessStep() { return this.currentStep === STEPS.SUCCESS; }

    // ── Confidence badges ──
    get patientConfidenceLabel() { return this._confidenceLabel(this.extraction.patientConfidence); }
    get hcpConfidenceLabel() { return this._confidenceLabel(this.extraction.hcpConfidence); }
    get programConfidenceLabel() { return this._confidenceLabel(this.extraction.programConfidence); }
    get payerConfidenceLabel() { return this._confidenceLabel(this.extraction.payerConfidence); }

    get patientConfidenceCss() { return this._confidenceCss(this.extraction.patientConfidence); }
    get hcpConfidenceCss() { return this._confidenceCss(this.extraction.hcpConfidence); }
    get programConfidenceCss() { return this._confidenceCss(this.extraction.programConfidence); }
    get payerConfidenceCss() { return this._confidenceCss(this.extraction.payerConfidence); }

    get isConfirmDisabled() {
        return !this.extraction.lastName || !this.extraction.programCode;
    }

    get languageOptions() {
        return [
            { label: 'English', value: 'English' },
            { label: 'Spanish', value: 'Spanish' },
            { label: 'French', value: 'French' },
            { label: 'Mandarin', value: 'Mandarin' },
            { label: 'Other', value: 'Other' }
        ];
    }

    get duplicateColumns() {
        return [
            { label: 'Name', fieldName: 'Name', type: 'text' },
            { label: 'Date of Birth', fieldName: 'PersonBirthdate', type: 'date' },
            { label: 'Phone', fieldName: 'Phone', type: 'phone' },
            { label: 'Email', fieldName: 'PersonEmail', type: 'email' },
            { label: 'City', fieldName: 'PersonMailingCity', type: 'text' }
        ];
    }

    // ── Event Handlers ──
    handleFileUpload(event) {
        this.documentId = event.detail.documentId;
        this.isLoading = true;

        extractFromDocument({ documentId: this.documentId })
            .then((result) => {
                this.extraction = JSON.parse(JSON.stringify(result));
                this.currentStep = STEPS.REVIEW;
                this._searchDuplicates();
            })
            .catch((error) => {
                this._showToast('Extraction Error', error.body?.message || 'Failed to extract data.', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.extraction[field] = event.target.value;

        // Re-check duplicates when patient identity fields change
        if (['firstName', 'lastName', 'dateOfBirth'].includes(field)) {
            this._searchDuplicates();
        }
    }

    handleDuplicateSelect(event) {
        const selected = event.detail.selectedRows;
        this.selectedExistingPatientId = selected.length > 0 ? selected[0].Id : null;
    }

    handleBack() {
        this.currentStep = STEPS.UPLOAD;
        this.extraction = {};
        this.duplicatePatients = [];
        this.selectedExistingPatientId = null;
    }

    handleReject() {
        this._showToast('Enrollment Rejected', 'The enrollment form has been rejected.', 'warning');
        this.handleBack();
    }

    handleConfirm() {
        this.isLoading = true;
        const extractionJson = JSON.stringify(this.extraction);

        confirmEnrollment({
            extractionJson: extractionJson,
            existingPatientId: this.selectedExistingPatientId
        })
            .then((result) => {
                this.enrollmentResult = result;
                this.currentStep = STEPS.SUCCESS;
                this._showToast('Success', 'Patient enrollment completed successfully!', 'success');
            })
            .catch((error) => {
                this._showToast('Enrollment Error', error.body?.message || 'Enrollment failed.', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleReset() {
        this.currentStep = STEPS.UPLOAD;
        this.extraction = {};
        this.duplicatePatients = [];
        this.enrollmentResult = {};
        this.selectedExistingPatientId = null;
        this.documentId = null;
    }

    // ── Private Helpers ──
    _searchDuplicates() {
        if (this.extraction.lastName) {
            searchDuplicatePatients({
                firstName: this.extraction.firstName || '',
                lastName: this.extraction.lastName,
                dob: this.extraction.dateOfBirth || null
            })
                .then((result) => {
                    this.duplicatePatients = result.map((p) => ({
                        ...p,
                        Name: (p.FirstName || '') + ' ' + p.LastName
                    }));
                })
                .catch(() => {
                    this.duplicatePatients = [];
                });
        }
    }

    _confidenceLabel(score) {
        if (score == null) return 'N/A';
        const pct = Math.round(score * 100);
        if (pct >= 90) return `${pct}% High`;
        if (pct >= 60) return `${pct}% Medium`;
        return `${pct}% Low`;
    }

    _confidenceCss(score) {
        if (score == null) return 'slds-m-left_x-small';
        const pct = score * 100;
        if (pct >= 90) return 'slds-m-left_x-small confidence-high';
        if (pct >= 60) return 'slds-m-left_x-small confidence-medium';
        return 'slds-m-left_x-small confidence-low';
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

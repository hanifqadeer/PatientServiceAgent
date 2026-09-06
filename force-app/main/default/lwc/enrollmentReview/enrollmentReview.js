import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import extractFromDocument from '@salesforce/apex/EnrollmentController.extractFromDocument';
import findPatientMatches from '@salesforce/apex/EnrollmentController.findPatientMatches';
import confirmEnrollment from '@salesforce/apex/EnrollmentController.confirmEnrollment';
import getActivePrograms from '@salesforce/apex/EnrollmentController.getActivePrograms';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const STEPS = {
    UPLOAD: 'upload',
    EXTRACTING: 'extracting',
    MATCH: 'match',
    REVIEW: 'review',
    SUCCESS: 'success'
};

/** Fields whose edits change who the patient is, so matches must be re-checked. */
const IDENTITY_FIELDS = ['firstName', 'lastName', 'dateOfBirth', 'email'];

/** Editable fields, in display order. Drives both the edited-field styling and the summary. */
const FIELD_LABELS = {
    // Document
    externalReferenceNumber: 'Form Reference Number',
    enrollmentDate: 'Date Received',
    enrollmentSource: 'Enrollment Source',
    // Patient
    firstName: 'First Name',
    lastName: 'Last Name',
    dateOfBirth: 'Date of Birth',
    phone: 'Phone',
    email: 'Email',
    street: 'Street',
    city: 'City',
    state: 'State',
    postalCode: 'Postal Code',
    country: 'Country',
    preferredLanguage: 'Preferred Language',
    communicationPreference: 'Communication Preference',
    // Prescriber
    hcpFirstName: 'HCP First Name',
    hcpLastName: 'HCP Last Name',
    hcpNpi: 'NPI Number',
    hcpSpecialty: 'Specialty',
    // Facility
    hcoName: 'Facility Name',
    hcoSiteType: 'Site Type',
    hcoTaxId: 'Tax ID',
    // Program
    careProgramId: 'Care Program',
    therapyArea: 'Therapy Area',
    productName: 'Product / Drug Name',
    // Payer
    payerName: 'Payer Name',
    memberId: 'Member ID',
    groupNumber: 'Group Number',
    coverageType: 'Coverage Type',
    // Consent
    patientConsentSigned: 'Patient Consent Signed',
    prescriberSignaturePresent: 'Prescriber Signature Present',
    servicesRequested: 'Requested Services'
};

/** Picklist values, matching the org's fields so a selection is always saveable. */
const COMMUNICATION_PREFERENCES = ['Phone', 'Email', 'Mail', 'Portal'];
const LANGUAGES = ['English', 'Spanish', 'French', 'Mandarin', 'Other'];
const SPECIALTIES = [
    'Oncology',
    'Rheumatology',
    'Neurology',
    'Dermatology',
    'Gastroenterology',
    'Internal Medicine',
    'Other'
];
const SITE_TYPES = ['Hospital', 'Clinic', 'Pharmacy', 'Infusion Center'];
const ENROLLMENT_SOURCES = ['Fax', 'eForm', 'Phone', 'HCP Referral', 'Web'];
const REQUESTED_SERVICES = [
    'Benefits Verification',
    'Prior Authorization',
    'Copay Assistance',
    'Free Drug / PAP',
    'Nurse Educator'
];

const toOptions = (values) => values.map((value) => ({ label: value, value }));

const EDITED_CSS = 'field field_edited';
const UNEDITED_CSS = 'field';

/**
 * @description Primary custom LWC — the enrollment specialist's workspace.
 *              Upload → AI extraction → patient match → human review/edit
 *              → confirm → create Patient + PSP.
 *
 *              Per architecture: "Human-reviewed extraction" (ADR-010).
 */
export default class EnrollmentReview extends NavigationMixin(LightningElement) {
    @track extraction = {};
    @track patientMatches = [];
    @track enrollmentResult = {};

    currentStep = STEPS.UPLOAD;
    isLoading = false;
    selectedExistingPatientId = null;
    documentId = null;
    fileName = null;

    /** Field names the specialist has changed since extraction, for the "edited" badges. */
    editedFields = new Set();

    // ── Step visibility ──
    get isUploadStep() { return this.currentStep === STEPS.UPLOAD; }
    get isExtractingStep() { return this.currentStep === STEPS.EXTRACTING; }
    get isMatchStep() { return this.currentStep === STEPS.MATCH; }
    get isReviewStep() { return this.currentStep === STEPS.REVIEW; }
    get isSuccessStep() { return this.currentStep === STEPS.SUCCESS; }

    /** The reading animation owns the extraction step, so no spinner on top of it. */
    get showSpinner() { return this.isLoading && !this.isExtractingStep; }

    // ── Warnings ──

    /**
     * Warnings were rendered as spans on one line, which ran together into an unreadable
     * paragraph. Numbering them makes each one a separate item the reviewer can work through.
     * The index is part of the key because two warnings can carry identical text.
     */
    get warningItems() {
        const warnings = this.extraction.warnings || [];
        return warnings.map((text, index) => ({
            key: `warning-${index}`,
            position: index + 1,
            text
        }));
    }

    get hasWarnings() { return this.warningItems.length > 0; }

    get warningHeading() {
        const count = this.warningItems.length;
        return count === 1
            ? '1 item needs your attention'
            : `${count} items need your attention`;
    }

    // ── Confidence badges ──
    get patientConfidenceLabel() { return this._confidenceLabel(this.extraction.patientConfidence); }
    get hcpConfidenceLabel() { return this._confidenceLabel(this.extraction.hcpConfidence); }
    get programConfidenceLabel() { return this._confidenceLabel(this.extraction.programConfidence); }
    get payerConfidenceLabel() { return this._confidenceLabel(this.extraction.payerConfidence); }

    get patientConfidenceCss() { return this._confidenceCss(this.extraction.patientConfidence); }
    get hcpConfidenceCss() { return this._confidenceCss(this.extraction.hcpConfidence); }
    get programConfidenceCss() { return this._confidenceCss(this.extraction.programConfidence); }
    get payerConfidenceCss() { return this._confidenceCss(this.extraction.payerConfidence); }

    // ── Edit tracking ──

    get editedCount() { return this.editedFields.size; }
    get hasEdits() { return this.editedFields.size > 0; }

    get editSummary() {
        const labels = this.editedFieldLabels;
        const noun = labels.length === 1 ? 'field' : 'fields';
        return `You changed ${labels.length} ${noun}: ${labels.join(', ')}. ` +
            'These values are saved with the enrollment, and update the patient record when you ' +
            'enroll an existing patient.';
    }

    get editedFieldLabels() {
        return Object.keys(FIELD_LABELS)
            .filter((field) => this.editedFields.has(field))
            .map((field) => FIELD_LABELS[field]);
    }

    /**
     * Per-field CSS, read in the template as {fieldClass.firstName}. Marks what the human
     * changed so a reviewer can tell their own corrections from what the model returned.
     */
    get fieldClass() {
        const classes = {};
        Object.keys(FIELD_LABELS).forEach((field) => {
            classes[field] = this.editedFields.has(field) ? EDITED_CSS : UNEDITED_CSS;
        });
        return classes;
    }

    // ── Provenance ──

    get extractionSummary() {
        if (!this.extraction.sourceFileName) {
            return null;
        }
        const mode = this.extraction.extractionMode === 'MOCK' ? 'Sample data' : 'AI extraction';
        return `${mode} from ${this.extraction.sourceFileName}`;
    }

    get isMockExtraction() { return this.extraction.extractionMode === 'MOCK'; }

    // ── Match step ──

    get matchHeading() {
        return this.patientMatches.length === 1
            ? 'This patient may already be in the system'
            : `${this.patientMatches.length} patients may match this form`;
    }

    get formPatientLabel() {
        const parts = [this.extraction.firstName, this.extraction.lastName].filter(Boolean);
        const name = parts.length ? parts.join(' ') : 'Unnamed patient';
        const dob = this.extraction.dateOfBirth ? ` · DOB ${this.extraction.dateOfBirth}` : '';
        const email = this.extraction.email ? ` · ${this.extraction.email}` : '';
        return `${name}${dob}${email}`;
    }

    /** Decorated for display: reason text, plan lines, and whether this one is selectable. */
    get decoratedMatches() {
        return this.patientMatches.map((match) => {
            const plans = (match.existingPlans || []).map((plan) => ({
                key: plan.planId,
                label: `${plan.programName || plan.programCode || 'Unknown program'} — ${plan.caseNumber} (${plan.status})`,
                isOpen: plan.isOpen
            }));
            return {
                ...match,
                reasonText: (match.matchReasons || []).join(' · '),
                planItems: plans,
                hasPlans: plans.length > 0,
                isStrong: match.strength === 'Strong',
                strengthCss: match.strength === 'Strong'
                    ? 'slds-m-left_x-small match-strong'
                    : 'slds-m-left_x-small match-possible',
                blockedReason: match.hasPlanForRequestedProgram
                    ? `Already has an open plan for ${this.extraction.programCode}. Choose a different program, or work the existing plan.`
                    : null,
                canEnroll: !match.hasPlanForRequestedProgram
            };
        });
    }

    get isConfirmDisabled() {
        return !this.extraction.lastName || !this.extraction.careProgramId;
    }

    get confirmLabel() {
        return this.selectedExistingPatientId
            ? 'Add Support Plan to Existing Patient'
            : 'Confirm Enrollment';
    }

    get selectedPatientBanner() {
        if (!this.selectedExistingPatientId) {
            return null;
        }
        const match = this.patientMatches.find((m) => m.patientId === this.selectedExistingPatientId);
        return match
            ? `Enrolling ${match.name} into a new support plan. Your edits below will update their patient record.`
            : null;
    }

    // ── Picklist options ──

    get languageOptions() { return toOptions(LANGUAGES); }
    get communicationOptions() { return toOptions(COMMUNICATION_PREFERENCES); }
    get specialtyOptions() { return toOptions(SPECIALTIES); }
    get siteTypeOptions() { return toOptions(SITE_TYPES); }
    get enrollmentSourceOptions() { return toOptions(ENROLLMENT_SOURCES); }
    get serviceOptions() { return toOptions(REQUESTED_SERVICES); }

    // ── Care Program lookup ──

    programs = [];
    programLoadError = null;

    @wire(getActivePrograms)
    wiredPrograms({ data, error }) {
        if (data) {
            this.programs = data;
            this.programLoadError = null;
        } else if (error) {
            this.programs = [];
            this.programLoadError = this._errorMessage(error) || 'Care programs could not be loaded.';
        }
    }

    /**
     * The program is chosen from the org's active programs rather than typed as a code.
     * A code read off a form is a string that may not exist; a selection is a record, and it is
     * the record the support plan links to.
     */
    get programOptions() {
        return this.programs.map((program) => ({
            label: `${program.Name} (${program.Program_Code__c})`,
            value: program.Id
        }));
    }

    /** Set when the model read a code that matched nothing active, so the UI can say so. */
    get unmatchedProgramCode() {
        return !this.extraction.careProgramId && this.extraction.programCode
            ? this.extraction.programCode
            : null;
    }

    // ── Success step ──

    get successHeadline() {
        return this.enrollmentResult.isNewPatient
            ? 'Patient enrolled'
            : 'Support plan added';
    }

    get successDetail() {
        const parts = [];
        if (this.enrollmentResult.patientName) {
            parts.push(this.enrollmentResult.patientName);
        }
        if (this.enrollmentResult.programName) {
            parts.push(this.enrollmentResult.programName);
        }
        if (this.enrollmentResult.planNumber) {
            parts.push(this.enrollmentResult.planNumber);
        }
        return parts.join(' · ');
    }

    get syncedFieldsMessage() {
        const fields = this.enrollmentResult.updatedPatientFields || [];
        if (!fields.length) {
            return null;
        }
        return `Updated on the existing patient record: ${fields.join(', ')}.`;
    }

    get documentLinkedMessage() {
        return this.enrollmentResult.documentLinked
            ? 'The enrollment form is attached to everything this enrollment produced.'
            : null;
    }

    /** Reports the prescriber and facility, and whether each was reused or created. */
    get providerSummary() {
        const parts = [];
        if (this.enrollmentResult.hcpName) {
            parts.push(
                `Prescriber: ${this.enrollmentResult.hcpName} (${
                    this.enrollmentResult.isNewHcp ? 'new record' : 'existing record'
                })`
            );
        }
        if (this.enrollmentResult.hcoName) {
            parts.push(
                `Facility: ${this.enrollmentResult.hcoName} (${
                    this.enrollmentResult.isNewHco ? 'new record' : 'existing record'
                })`
            );
        }
        return parts.length ? parts.join(' · ') : null;
    }

    get affiliationMessage() {
        const created = this.enrollmentResult.affiliationsCreated;
        if (!created) {
            return null;
        }
        return created === 1
            ? '1 relationship recorded.'
            : `${created} relationships recorded.`;
    }

    /**
     * Surfaced rather than swallowed. The enrollment succeeded, but somebody looking for the
     * prescriber on the patient record needs to know why it is not there.
     */
    get affiliationError() {
        return this.enrollmentResult.affiliationError
            ? `The patient and support plan were created, but the provider relationships could not be recorded: ${this.enrollmentResult.affiliationError}`
            : null;
    }

    get hasHcp() { return Boolean(this.enrollmentResult.hcpId); }

    // ── Event Handlers ──

    handleFileUpload(event) {
        this.documentId = event.detail.documentId;
        this.fileName = event.detail.files?.[0]?.name;
        this.currentStep = STEPS.EXTRACTING;
        this.isLoading = true;

        extractFromDocument({ documentId: this.documentId })
            .then((result) => {
                this.extraction = JSON.parse(JSON.stringify(result));
                this.editedFields = new Set();
                return this._loadPatientMatches();
            })
            .catch((error) => {
                this.currentStep = STEPS.UPLOAD;
                this._showError('Extraction Error', error, 'The document could not be read.');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleFieldChange(event) {
        this._applyEdit(event.target.dataset.field, event.target.value);
    }

    _applyEdit(field, value) {
        if (!field || this.extraction[field] === value) {
            return;
        }

        // Reassign rather than mutate so every getter derived from extraction recomputes.
        this.extraction = { ...this.extraction, [field]: value };
        this.editedFields = new Set(this.editedFields).add(field);

        // Editing who the patient is invalidates the match we ran on the extracted values.
        if (IDENTITY_FIELDS.includes(field)) {
            this.selectedExistingPatientId = null;
            this._refreshMatchesQuietly();
        }
    }

    /** Checkboxes report state on `checked`, not `value`. */
    handleCheckboxChange(event) {
        this._applyEdit(event.target.dataset.field, event.target.checked);
    }

    /** lightning-checkbox-group reports an array of selected values. */
    handleServicesChange(event) {
        this._applyEdit('servicesRequested', event.detail.value);
    }

    /**
     * Selecting a program carries its name, therapy area and product across too. Those come from
     * the record rather than the document, so a misread therapy area on a fax cannot contradict
     * the program catalog.
     */
    handleProgramChange(event) {
        const careProgramId = event.detail.value;
        const program = this.programs.find((candidate) => candidate.Id === careProgramId);

        this.extraction = {
            ...this.extraction,
            careProgramId,
            programCode: program ? program.Program_Code__c : this.extraction.programCode,
            programName: program ? program.Name : this.extraction.programName,
            therapyArea: program ? program.Therapy_Area__c : this.extraction.therapyArea,
            productName: program ? program.Product_Name__c : this.extraction.productName
        };
        this.editedFields = new Set(this.editedFields).add('careProgramId');
    }

    handleSelectExistingPatient(event) {
        this.selectedExistingPatientId = event.target.dataset.patientId;
        this.currentStep = STEPS.REVIEW;
    }

    handleCreateNewPatient() {
        this.selectedExistingPatientId = null;
        this.currentStep = STEPS.REVIEW;
    }

    handleViewMatchedPatient(event) {
        this._navigateToRecord(event.target.dataset.patientId);
    }

    handleBackToMatches() {
        if (this.patientMatches.length) {
            this.currentStep = STEPS.MATCH;
        }
    }

    handleBack() {
        this._resetToUpload();
    }

    handleReject() {
        this._showToast('Enrollment Rejected', 'The enrollment form has been rejected.', 'warning');
        this._resetToUpload();
    }

    handleConfirm() {
        this.isLoading = true;

        confirmEnrollment({
            extractionJson: JSON.stringify(this.extraction),
            existingPatientId: this.selectedExistingPatientId,
            documentId: this.documentId
        })
            .then((result) => {
                this.enrollmentResult = result;
                this.currentStep = STEPS.SUCCESS;
                this._showToast(
                    'Success',
                    result.isNewPatient
                        ? 'Patient enrolled and support plan created.'
                        : 'New support plan added to the existing patient.',
                    'success'
                );
            })
            .catch((error) => {
                // Stay on the review step. The specialist needs to fix something here, and
                // moving on would imply the enrollment was created when it was not.
                this._showError('Enrollment Not Created', error, 'The enrollment could not be saved.');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleViewPatient() {
        this._navigateToRecord(this.enrollmentResult.patientId);
    }

    handleViewPlan() {
        this._navigateToRecord(this.enrollmentResult.planId);
    }

    handleViewPrescriber() {
        this._navigateToRecord(this.enrollmentResult.hcpId);
    }

    handleReset() {
        this._resetToUpload();
    }

    // ── Private Helpers ──

    _loadPatientMatches() {
        return findPatientMatches({ extractionJson: JSON.stringify(this.extraction) })
            .then((matches) => {
                this.patientMatches = matches || [];
                // Only interrupt the specialist when there is a decision to make.
                this.currentStep = this.patientMatches.length ? STEPS.MATCH : STEPS.REVIEW;
            })
            .catch((error) => {
                // A failed match check must not block enrollment, but it must be visible:
                // silently proceeding is how duplicate patients get created.
                this.patientMatches = [];
                this.currentStep = STEPS.REVIEW;
                this._showError(
                    'Duplicate Check Unavailable',
                    error,
                    'Could not check for existing patients. Review carefully before confirming.'
                );
            });
    }

    /** Re-runs matching after an identity edit without hijacking the screen. */
    _refreshMatchesQuietly() {
        findPatientMatches({ extractionJson: JSON.stringify(this.extraction) })
            .then((matches) => {
                this.patientMatches = matches || [];
            })
            .catch(() => {
                this.patientMatches = [];
            });
    }

    _resetToUpload() {
        this.currentStep = STEPS.UPLOAD;
        this.extraction = {};
        this.patientMatches = [];
        this.enrollmentResult = {};
        this.selectedExistingPatientId = null;
        this.documentId = null;
        this.fileName = null;
        this.editedFields = new Set();
    }

    _navigateToRecord(recordId) {
        if (!recordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
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

    /**
     * Pulls the real server message out of an Apex error.
     *
     * error.body.message carries what Apex put in the AuraHandledException; body.pageErrors and
     * fieldErrors carry validation-rule and DML failures, which land nowhere near body.message.
     * Falling straight through to a generic string is what made failures look like successes.
     */
    _showError(title, error, fallback) {
        this._showToast(title, this._errorMessage(error) || fallback, 'error');
    }

    _errorMessage(error) {
        const body = error?.body;
        if (!body) {
            return error?.message || null;
        }
        if (Array.isArray(body)) {
            return body.map((e) => e.message).filter(Boolean).join('; ') || null;
        }
        if (body.pageErrors?.length) {
            return body.pageErrors.map((e) => e.message).join('; ');
        }
        if (body.fieldErrors && Object.keys(body.fieldErrors).length) {
            return Object.values(body.fieldErrors)
                .flat()
                .map((e) => e.message)
                .join('; ');
        }
        if (body.output?.errors?.length) {
            return body.output.errors.map((e) => e.message).join('; ');
        }
        return body.message || null;
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant, mode: variant === 'error' ? 'sticky' : 'dismissable' })
        );
    }
}

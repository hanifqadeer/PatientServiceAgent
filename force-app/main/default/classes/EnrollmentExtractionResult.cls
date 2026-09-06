/**
 * @description DTO/Wrapper class for AI enrollment extraction results.
 *              Holds structured data extracted from enrollment documents
 *              (patient identity, HCP info, program indicators, payer info)
 *              along with per-field confidence scores.
 *              Designed for future swap-in of real AI service — mock returns
 *              synthetic data with this same structure.
 */
public with sharing class EnrollmentExtractionResult {

    // ── Patient Identity ──
    @AuraEnabled public String firstName;
    @AuraEnabled public String lastName;
    @AuraEnabled public Date dateOfBirth;
    @AuraEnabled public String phone;
    @AuraEnabled public String email;
    @AuraEnabled public String street;
    @AuraEnabled public String city;
    @AuraEnabled public String state;
    @AuraEnabled public String postalCode;
    @AuraEnabled public String country;
    @AuraEnabled public String preferredLanguage;
    @AuraEnabled public String communicationPreference;

    // ── HCP Information ──
    @AuraEnabled public String hcpFirstName;
    @AuraEnabled public String hcpLastName;
    @AuraEnabled public String hcpNpi;
    @AuraEnabled public String hcpSpecialty;

    // ── HCO Information ──
    @AuraEnabled public String hcoName;
    @AuraEnabled public String hcoSiteType;
    @AuraEnabled public String hcoTaxId;

    // ── Program / Therapy ──
    /**
     * Resolved Care Program record. The model returns a code; AIExtractionService matches it
     * against the org's active programs and stamps the Id here, so the review UI can offer a
     * real selection and the plan links to a record rather than to a string that may not exist.
     */
    @AuraEnabled public String careProgramId;
    @AuraEnabled public String programCode;
    @AuraEnabled public String programName;
    @AuraEnabled public String therapyArea;
    @AuraEnabled public String productName;

    // ── Payer Information ──
    @AuraEnabled public String payerName;
    @AuraEnabled public String memberId;
    @AuraEnabled public String groupNumber;
    @AuraEnabled public String coverageType;

    // ── Enrollment Metadata ──
    @AuraEnabled public String enrollmentSource;
    @AuraEnabled public Date enrollmentDate;
    /** The form's own intake number, e.g. ENR-2026-00417. Maps to Case.External_Reference_Number__c. */
    @AuraEnabled public String externalReferenceNumber;
    @AuraEnabled public Boolean patientConsentSigned;
    @AuraEnabled public Boolean prescriberSignaturePresent;
    /**
     * Services ticked on the form (Benefits Verification, Prior Authorization, ...).
     * Captured for the reviewer and for the child-Case automation that follows; nothing
     * downstream consumes it yet.
     */
    @AuraEnabled public List<String> servicesRequested;

    // ── Provenance ──
    // Stamped on every result so a confirmed enrollment can be traced back to the file
    // and the prompt template that produced it.
    @AuraEnabled public String extractionMode; // 'AI' or 'MOCK'
    @AuraEnabled public String sourceDocumentId;
    @AuraEnabled public String sourceFileName;
    @AuraEnabled public String documentType;
    @AuraEnabled public String promptTemplate;
    @AuraEnabled public Datetime extractedAt;

    // ── Confidence Scores (0.0 – 1.0 per field group) ──
    @AuraEnabled public Decimal patientConfidence;
    @AuraEnabled public Decimal hcpConfidence;
    @AuraEnabled public Decimal programConfidence;
    @AuraEnabled public Decimal payerConfidence;

    /**
     * The weakest section score, not an average. An average hides the one section that
     * was unreadable behind three that were clean, which is exactly the case a reviewer
     * needs flagged.
     */
    @AuraEnabled public Decimal overallConfidence;

    // ── Overall extraction status ──
    @AuraEnabled public Boolean isComplete;
    @AuraEnabled public List<String> warnings;

    public EnrollmentExtractionResult() {
        this.warnings = new List<String>();
        this.servicesRequested = new List<String>();
        this.isComplete = false;
        this.patientConfidence = 0.0;
        this.hcpConfidence = 0.0;
        this.programConfidence = 0.0;
        this.payerConfidence = 0.0;
        this.overallConfidence = 0.0;
    }
}
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

    // ── Program / Therapy ──
    @AuraEnabled public String programCode;
    @AuraEnabled public String programName;
    @AuraEnabled public String therapyArea;
    @AuraEnabled public String productName;

    // ── Payer Information ──
    @AuraEnabled public String payerName;
    @AuraEnabled public String memberId;
    @AuraEnabled public String groupNumber;

    // ── Enrollment Metadata ──
    @AuraEnabled public String enrollmentSource;

    // ── Confidence Scores (0.0 – 1.0 per field group) ──
    @AuraEnabled public Decimal patientConfidence;
    @AuraEnabled public Decimal hcpConfidence;
    @AuraEnabled public Decimal programConfidence;
    @AuraEnabled public Decimal payerConfidence;

    // ── Overall extraction status ──
    @AuraEnabled public Boolean isComplete;
    @AuraEnabled public List<String> warnings;

    public EnrollmentExtractionResult() {
        this.warnings = new List<String>();
        this.isComplete = false;
        this.patientConfidence = 0.0;
        this.hcpConfidence = 0.0;
        this.programConfidence = 0.0;
        this.payerConfidence = 0.0;
    }
}

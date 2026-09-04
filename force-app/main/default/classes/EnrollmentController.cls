/**
 * @description Thin Apex controller for the Enrollment Review LWC.
 *              Exposes @AuraEnabled methods that delegate to services.
 *              Per architecture: "Controller is a UI-facing boundary."
 */
public with sharing class EnrollmentController {

    /**
     * @description Trigger AI extraction from an uploaded document.
     * @param documentId The ContentDocument Id of the uploaded file.
     * @return EnrollmentExtractionResult with extracted data and confidence scores.
     */
    @AuraEnabled
    public static EnrollmentExtractionResult extractFromDocument(Id documentId) {
        try {
            AIExtractionService aiService = new AIExtractionService();
            return aiService.extractEnrollmentData(documentId);
        } catch (Exception e) {
            throw new AuraHandledException('Extraction failed: ' + e.getMessage());
        }
    }

    /**
     * @description Search for potential duplicate patients.
     * @param firstName Patient first name.
     * @param lastName Patient last name.
     * @param dob Patient date of birth (ISO string parsed).
     * @return List of matching patient accounts.
     */
    @AuraEnabled
    public static List<Account> searchDuplicatePatients(String firstName, String lastName, Date dob) {
        try {
            PatientService svc = new PatientService();
            return svc.findDuplicates(firstName, lastName, dob);
        } catch (Exception e) {
            throw new AuraHandledException('Duplicate search failed: ' + e.getMessage());
        }
    }

    /**
     * @description Get list of active Care Programs for selection.
     * @return List of active Care Programs.
     */
    @AuraEnabled(cacheable=true)
    public static List<Care_Program__c> getActivePrograms() {
        try {
            CareProgramService svc = new CareProgramService();
            return svc.getActivePrograms();
        } catch (Exception e) {
            throw new AuraHandledException('Failed to load programs: ' + e.getMessage());
        }
    }

    /**
     * @description Process the confirmed enrollment.
     * @param extractionJson JSON-serialized EnrollmentExtractionResult (edited by specialist).
     * @param existingPatientId Selected existing patient Id (null for new patient).
     * @return EnrollmentResult with created record Ids.
     */
    @AuraEnabled
    public static EnrollmentService.EnrollmentResult confirmEnrollment(
            String extractionJson, Id existingPatientId) {
        try {
            EnrollmentExtractionResult extraction =
                (EnrollmentExtractionResult) JSON.deserialize(
                    extractionJson, EnrollmentExtractionResult.class);
            EnrollmentService svc = new EnrollmentService();
            return svc.processEnrollment(extraction, existingPatientId);
        } catch (Exception e) {
            throw new AuraHandledException('Enrollment failed: ' + e.getMessage());
        }
    }
}

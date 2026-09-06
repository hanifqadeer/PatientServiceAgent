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
            throw uiError('Extraction failed: ' + e.getMessage());
        }
    }

    /**
     * @description Find patients who may already be the person on the form, with the plans
     *              they already hold, so the specialist can add a program to an existing
     *              patient instead of creating a duplicate.
     * @param extractionJson JSON-serialized EnrollmentExtractionResult (as reviewed).
     * @return Candidate matches, strongest first. Empty when the patient looks new.
     */
    @AuraEnabled
    public static List<PatientMatchResult> findPatientMatches(String extractionJson) {
        try {
            EnrollmentExtractionResult extraction = deserializeExtraction(extractionJson);
            return new PatientService().findMatches(extraction);
        } catch (Exception e) {
            throw uiError('Patient match check failed: ' + e.getMessage());
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
            throw uiError('Duplicate search failed: ' + e.getMessage());
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
            throw uiError('Failed to load programs: ' + e.getMessage());
        }
    }

    /**
     * @description Process the confirmed enrollment.
     * @param extractionJson JSON-serialized EnrollmentExtractionResult (edited by specialist).
     * @param existingPatientId Selected existing patient Id (null for new patient).
     * @param documentId ContentDocument id of the source form, linked to what gets created.
     * @return EnrollmentResult with created record Ids.
     */
    @AuraEnabled
    public static EnrollmentService.EnrollmentResult confirmEnrollment(
            String extractionJson, Id existingPatientId, Id documentId) {
        try {
            EnrollmentExtractionResult extraction = deserializeExtraction(extractionJson);
            EnrollmentService svc = new EnrollmentService();
            return svc.processEnrollment(extraction, existingPatientId, documentId);
        } catch (Exception e) {
            throw uiError(e.getMessage());
        }
    }

    private static EnrollmentExtractionResult deserializeExtraction(String extractionJson) {
        if (String.isBlank(extractionJson)) {
            throw new EnrollmentControllerException('No enrollment data was submitted.');
        }
        return (EnrollmentExtractionResult) JSON.deserialize(
            extractionJson, EnrollmentExtractionResult.class);
    }

    /**
     * Builds an AuraHandledException whose message actually reaches the browser.
     *
     * The constructor alone is not enough: `new AuraHandledException(msg)` sets an internal
     * message but leaves getMessage() returning "Script-thrown exception", which is what the
     * LWC reads from error.body.message. Callers then see a useless string, or nothing, and
     * the failure looks like it silently succeeded. setMessage() is what fixes that.
     */
    private static AuraHandledException uiError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }

    public class EnrollmentControllerException extends Exception {}
}

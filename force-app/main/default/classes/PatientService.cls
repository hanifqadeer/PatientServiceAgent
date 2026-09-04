/**
 * @description Reusable service for Patient (Person Account) operations.
 *              Handles patient creation, duplicate detection, and search.
 *              Delegates queries to PatientSelector.
 *              Bulk-safe — accepts collections, no SOQL/DML in loops.
 */
public with sharing class PatientService {

    private PatientSelector selector;

    public PatientService() {
        this.selector = new PatientSelector();
    }

    /**
     * @description Search for potential duplicate patients by name and DOB.
     * @param firstName Patient first name.
     * @param lastName Patient last name.
     * @param dob Patient date of birth.
     * @return List of matching patient records (may be empty).
     */
    public List<Account> findDuplicates(String firstName, String lastName, Date dob) {
        return selector.findByNameAndDob(firstName, lastName, dob);
    }

    /**
     * @description Create a new Patient person account from extraction data.
     *              Sets record type, name, DOB, contact info, and preferences.
     * @param extraction The extracted enrollment data.
     * @return The newly inserted Patient Account.
     */
    public Account createPatient(EnrollmentExtractionResult extraction) {
        if (extraction == null || String.isBlank(extraction.lastName)) {
            throw new PatientServiceException('Patient last name is required for creation.');
        }

        Id patientRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Patient')
            .getRecordTypeId();

        Account patient = new Account(
            FirstName = extraction.firstName,
            LastName = extraction.lastName,
            PersonBirthdate = extraction.dateOfBirth,
            Phone = extraction.phone,
            PersonEmail = extraction.email,
            PersonMailingStreet = extraction.street,
            PersonMailingCity = extraction.city,
            PersonMailingState = extraction.state,
            PersonMailingPostalCode = extraction.postalCode,
            Preferred_Language__c = extraction.preferredLanguage,
            Communication_Preference__c = extraction.communicationPreference
        );
        patient.put('RecordTypeId', patientRtId);

        insert patient;
        return patient;
    }

    /**
     * @description Get patient records by IDs with all key fields.
     * @param patientIds Set of Account IDs.
     * @return List of Patient accounts.
     */
    public List<Account> getPatients(Set<Id> patientIds) {
        return selector.getByIds(patientIds);
    }

    /**
     * @description Get patients with their associated Support Plans.
     * @param patientIds Set of Account IDs.
     * @return List of Patient accounts with nested PSP Cases.
     */
    public List<Account> getPatientsWithPlans(Set<Id> patientIds) {
        return selector.getWithSupportPlans(patientIds);
    }

    public class PatientServiceException extends Exception {}
}

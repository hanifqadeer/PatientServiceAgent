/**
 * @description Centralized data access layer for Patient (Person Account) queries.
 *              Consolidates reused query patterns to avoid SOQL duplication.
 *              All methods run with sharing to respect record-level access.
 *
 *              Why a Selector? The architecture pattern is:
 *              LWC → Controller → Service → Selector → Salesforce
 *              Selectors centralize query logic so Services focus on business logic.
 */
public with sharing class PatientSelector {

    private static final String PATIENT_RT = 'Patient';

    /**
     * @description Get Patient person accounts by a set of Account Ids.
     * @param accountIds Set of Account Ids to query.
     * @return List of matching Patient accounts with key fields.
     */
    public List<Account> getByIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Account>();
        }
        return [
            SELECT Id, FirstName, LastName, PersonBirthdate, PersonEmail,
                   PersonMailingStreet, PersonMailingCity, PersonMailingState,
                   PersonMailingPostalCode, Phone,
                   Preferred_Language__c, Communication_Preference__c,
                   RecordType.DeveloperName
            FROM Account
            WHERE Id IN :accountIds
              AND RecordType.DeveloperName = :PATIENT_RT
        ];
    }

    /**
     * @description Search patients by first name, last name, and date of birth.
     *              Used for duplicate detection during enrollment.
     * @param firstName Patient first name (partial match).
     * @param lastName Patient last name (exact match).
     * @param dob Patient date of birth (exact match).
     * @return List of potential duplicate patients.
     */
    public List<Account> findByNameAndDob(String firstName, String lastName, Date dob) {
        if (String.isBlank(lastName) || dob == null) {
            return new List<Account>();
        }
        String firstNameFilter = String.isNotBlank(firstName) ? firstName + '%' : '%';
        return [
            SELECT Id, FirstName, LastName, PersonBirthdate, PersonEmail,
                   Phone, PersonMailingCity, PersonMailingState,
                   RecordType.DeveloperName
            FROM Account
            WHERE RecordType.DeveloperName = :PATIENT_RT
              AND LastName = :lastName
              AND FirstName LIKE :firstNameFilter
              AND PersonBirthdate = :dob
            LIMIT 50
        ];
    }

    /**
     * @description Get patients with their related Patient Support Plans (PSP Cases).
     * @param accountIds Set of Account Ids.
     * @return List of Patient accounts with nested Cases (PSP record type).
     */
    public List<Account> getWithSupportPlans(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Account>();
        }
        String query = 'SELECT Id, FirstName, LastName, PersonBirthdate, Phone, PersonEmail, ' +
                       'Preferred_Language__c, Communication_Preference__c, ' +
                       '(SELECT Id, CaseNumber, Subject, Status, Priority, ' +
                       'Care_Program__c, Care_Program__r.Name, Primary_Care_Coordinator__c, ' +
                       'Primary_Care_Coordinator__r.Name, Enrollment_Date__c, Plan_Start_Date__c, ' +
                       'Plan_End_Date__c, Support_Level__c FROM Cases ' +
                       'WHERE RecordType.DeveloperName = \'Patient_Support_Plan\' ORDER BY CreatedDate DESC) ' +
                       'FROM Account WHERE Id IN :accountIds AND RecordType.DeveloperName = :PATIENT_RT';
        return Database.query(query);
    }
}

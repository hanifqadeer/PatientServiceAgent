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
     * @description Find patients who might already be the person on an enrollment form, with
     *              the plans each of them already holds.
     *
     *              This is what turns "create another patient" into "add a program to the
     *              patient we already have". The plans matter as much as the match: a patient
     *              who already holds an open plan for the same program is a duplicate
     *              enrollment, while one holding a plan for a different program is exactly the
     *              case this flow should support.
     *
     * @param extraction The reviewed extraction data.
     * @return Candidate matches, strongest first. Empty when nothing matches.
     */
    public List<PatientMatchResult> findMatches(EnrollmentExtractionResult extraction) {
        if (extraction == null) {
            return new List<PatientMatchResult>();
        }

        List<Account> candidates = selector.findMatches(
            extraction.firstName,
            extraction.lastName,
            extraction.dateOfBirth,
            extraction.email
        );
        if (candidates.isEmpty()) {
            return new List<PatientMatchResult>();
        }

        Map<Id, List<Case>> plansByPatient = groupPlansByPatient(candidates);

        List<PatientMatchResult> strong = new List<PatientMatchResult>();
        List<PatientMatchResult> possible = new List<PatientMatchResult>();

        for (Account candidate : candidates) {
            PatientMatchResult match = buildMatch(candidate, extraction, plansByPatient);
            if (match.strength == PatientMatchResult.STRENGTH_STRONG) {
                strong.add(match);
            } else {
                possible.add(match);
            }
        }

        strong.addAll(possible);
        return strong;
    }

    private Map<Id, List<Case>> groupPlansByPatient(List<Account> candidates) {
        Set<Id> candidateIds = new Set<Id>();
        for (Account candidate : candidates) {
            candidateIds.add(candidate.Id);
        }

        Map<Id, List<Case>> plansByPatient = new Map<Id, List<Case>>();
        for (Case plan : selector.getSupportPlansFor(candidateIds)) {
            if (!plansByPatient.containsKey(plan.AccountId)) {
                plansByPatient.put(plan.AccountId, new List<Case>());
            }
            plansByPatient.get(plan.AccountId).add(plan);
        }
        return plansByPatient;
    }

    private PatientMatchResult buildMatch(
        Account candidate,
        EnrollmentExtractionResult extraction,
        Map<Id, List<Case>> plansByPatient
    ) {
        PatientMatchResult match = new PatientMatchResult();
        match.patientId = candidate.Id;
        match.name = ((candidate.FirstName == null ? '' : candidate.FirstName) + ' ' + candidate.LastName).trim();
        match.email = candidate.PersonEmail;
        match.phone = candidate.Phone;
        match.birthdate = candidate.PersonBirthdate;
        match.city = candidate.PersonMailingCity;

        if (String.isNotBlank(extraction.email)
            && extraction.email.equalsIgnoreCase(candidate.PersonEmail)) {
            match.matchReasons.add('Same email address');
            match.strength = PatientMatchResult.STRENGTH_STRONG;
        }
        if (extraction.dateOfBirth != null && extraction.dateOfBirth == candidate.PersonBirthdate) {
            match.matchReasons.add('Same date of birth');
        }
        if (String.isNotBlank(extraction.lastName)
            && extraction.lastName.equalsIgnoreCase(candidate.LastName)) {
            match.matchReasons.add('Same last name');
        }
        if (String.isNotBlank(extraction.firstName)
            && extraction.firstName.equalsIgnoreCase(candidate.FirstName)) {
            match.matchReasons.add('Same first name');
        }

        for (Case plan : plansByPatient.get(candidate.Id) == null
            ? new List<Case>()
            : plansByPatient.get(candidate.Id)) {
            PatientMatchResult.PlanSummary summary = new PatientMatchResult.PlanSummary();
            summary.planId = plan.Id;
            summary.caseNumber = plan.CaseNumber;
            summary.status = plan.Status;
            summary.isOpen = plan.IsClosed == false;
            summary.enrollmentDate = plan.Enrollment_Date__c;
            summary.programName = plan.Care_Program__r == null ? null : plan.Care_Program__r.Name;
            summary.programCode = plan.Care_Program__r == null ? null : plan.Care_Program__r.Program_Code__c;
            match.existingPlans.add(summary);

            if (summary.isOpen
                && String.isNotBlank(extraction.programCode)
                && extraction.programCode.equalsIgnoreCase(summary.programCode)) {
                match.hasPlanForRequestedProgram = true;
            }
        }
        return match;
    }

    /**
     * @description Apply reviewed enrollment data onto an existing patient.
     *
     *              A specialist who corrects a phone number on the review screen expects that
     *              correction to reach the patient record. Only non-blank incoming values that
     *              actually differ are written, so a form missing a field never blanks out data
     *              already held.
     *
     * @param patient The existing patient. Must carry the fields compared below.
     * @param extraction The reviewed extraction data.
     * @return Labels of the fields that changed. Empty when nothing changed and no DML ran.
     */
    public List<String> syncPatient(Account patient, EnrollmentExtractionResult extraction) {
        List<String> changed = new List<String>();
        if (patient == null || extraction == null) {
            return changed;
        }

        Map<String, String> incoming = new Map<String, String>{
            'FirstName' => extraction.firstName,
            'Phone' => extraction.phone,
            'PersonEmail' => extraction.email,
            'PersonMailingStreet' => extraction.street,
            'PersonMailingCity' => extraction.city,
            'PersonMailingPostalCode' => extraction.postalCode,
            'Preferred_Language__c' => extraction.preferredLanguage,
            'Communication_Preference__c' => extraction.communicationPreference
        };
        Map<String, String> labels = new Map<String, String>{
            'FirstName' => 'First Name',
            'Phone' => 'Phone',
            'PersonEmail' => 'Email',
            'PersonMailingStreet' => 'Street',
            'PersonMailingCity' => 'City',
            'PersonMailingPostalCode' => 'Postal Code',
            'Preferred_Language__c' => 'Preferred Language',
            'Communication_Preference__c' => 'Communication Preference'
        };

        for (String field : incoming.keySet()) {
            String value = incoming.get(field);
            if (String.isBlank(value)) {
                continue;
            }
            Object current = patient.get(field);
            if (current == null || !value.equals(String.valueOf(current))) {
                patient.put(field, value);
                changed.add(labels.get(field));
            }
        }

        if (extraction.dateOfBirth != null && extraction.dateOfBirth != patient.PersonBirthdate) {
            patient.PersonBirthdate = extraction.dateOfBirth;
            changed.add('Date of Birth');
        }

        changed.addAll(syncAddressLocale(patient, extraction));

        if (!changed.isEmpty()) {
            update patient;
        }
        return changed;
    }

    /**
     * State and country are set together, never independently.
     *
     * With state and country picklists enabled, writing PersonMailingStateCode on a record that
     * has no country fails with "A country/territory must be specified before specifying a state
     * value". Enrollment forms print a state and almost never print a country, so this is the
     * normal case, not an edge one. Matches the US default createPatient already applies.
     *
     * @return Labels of the fields that changed. Country is reported only when the form actually
     *         stated one — the implicit US default is not a reviewer edit.
     */
    private List<String> syncAddressLocale(Account patient, EnrollmentExtractionResult extraction) {
        List<String> changed = new List<String>();
        String currentCountry = (String) patient.get('PersonMailingCountryCode');

        if (String.isNotBlank(extraction.country) && !extraction.country.equals(currentCountry)) {
            patient.put('PersonMailingCountryCode', extraction.country);
            currentCountry = extraction.country;
            changed.add('Country');
        }

        if (String.isBlank(extraction.state)) {
            return changed;
        }
        if (String.isBlank(currentCountry)) {
            patient.put('PersonMailingCountryCode', 'US');
        }
        if (!extraction.state.equals((String) patient.get('PersonMailingStateCode'))) {
            patient.put('PersonMailingStateCode', extraction.state);
            changed.add('State');
        }
        return changed;
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
            PersonMailingStateCode = extraction.state,
            PersonMailingPostalCode = extraction.postalCode,
            PersonMailingCountryCode = String.isNotBlank(extraction.country)
                ? extraction.country : 'US',
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
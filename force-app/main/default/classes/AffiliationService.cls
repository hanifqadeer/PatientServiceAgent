/**
 * @description Records the relationships an enrollment form establishes: the patient to their
 *              prescriber, and that prescriber to the treatment facility.
 *
 *              Per the architecture data model, Affiliation__c is the single junction for all
 *              party relationships, so both links are the same object with a different
 *              Affiliation_Type__c.
 *
 *              Existing links are never duplicated. A patient enrolling into a second program
 *              with the same prescriber must not gain a second identical affiliation.
 *
 *              Writing an affiliation needs field-level security on Role__c, Is_Primary__c,
 *              Status__c and the effective dates. Without it the insert fails with "fields
 *              being inaccessible", and the fields do not even appear in a describe — which
 *              reads convincingly like the fields do not exist. The persona permission sets
 *              grant them; a user who has neither still enrolls successfully, and the reason
 *              the relationships are missing is reported rather than swallowed.
 */
public with sharing class AffiliationService {
    public static final String TYPE_PATIENT_HCP = 'Patient-HCP';
    public static final String TYPE_HCP_HCO = 'HCP-HCO';

    private static final String ROLE_PRESCRIBER = 'Prescriber';
    private static final String ROLE_AFFILIATED = 'Affiliated';
    private static final String STATUS_ACTIVE = 'Active';

    /** Set when the affiliations could not be written. Null on success. */
    public String lastError { get; private set; }

    /**
     * @description Create the affiliations an enrollment implies, skipping any that already exist.
     * @param patientId The enrolled patient.
     * @param hcpId The prescribing provider. Null when the form named none.
     * @param hcoId The treatment facility. Null when the form named none.
     * @return The affiliations actually inserted. Empty when everything already existed, and
     *         also when the write failed — check lastError to tell those apart.
     */
    public List<Affiliation__c> linkEnrollment(Id patientId, Id hcpId, Id hcoId) {
        lastError = null;
        List<Affiliation__c> toInsert = new List<Affiliation__c>();

        try {
            if (patientId != null && hcpId != null && !exists(patientId, hcpId, TYPE_PATIENT_HCP)) {
                toInsert.add(build(patientId, hcpId, TYPE_PATIENT_HCP, ROLE_PRESCRIBER, true));
            }
            if (hcpId != null && hcoId != null && !exists(hcpId, hcoId, TYPE_HCP_HCO)) {
                toInsert.add(build(hcpId, hcoId, TYPE_HCP_HCO, ROLE_AFFILIATED, false));
            }

            if (!toInsert.isEmpty()) {
                insert toInsert;
            }
            return toInsert;
        } catch (Exception e) {
            // An affiliation is supporting data. The patient, their plan and the onboarding task
            // are the enrollment, and they have already been created by this point — losing all
            // of that because a relationship record could not be written would be the wrong
            // trade. The failure is reported on the result and shown in the review UI rather
            // than swallowed, so nobody is left believing the links exist.
            lastError = e.getMessage();
            return new List<Affiliation__c>();
        }
    }

    private Boolean exists(Id accountOne, Id accountTwo, String affiliationType) {
        return [
            SELECT COUNT()
            FROM Affiliation__c
            WHERE Account_1__c = :accountOne
              AND Account_2__c = :accountTwo
              AND Affiliation_Type__c = :affiliationType
        ] > 0;
    }

    private Affiliation__c build(
        Id accountOne,
        Id accountTwo,
        String affiliationType,
        String role,
        Boolean isPrimary
    ) {
        return new Affiliation__c(
            Account_1__c = accountOne,
            Account_2__c = accountTwo,
            Affiliation_Type__c = affiliationType,
            Role__c = role,
            Is_Primary__c = isPrimary,
            Status__c = STATUS_ACTIVE,
            Effective_Start_Date__c = Date.today()
        );
    }

}

/**
 * @description One candidate patient found while checking whether an uploaded enrollment form
 *              belongs to somebody already in the system.
 *
 *              Carries the reasons the match fired and the plans that patient already holds, so
 *              the specialist can answer the only question that matters at that moment: is this
 *              a new patient, or a new program for a patient we already have?
 */
public with sharing class PatientMatchResult {
    /** Matched on something that identifies a person uniquely, such as email. */
    public static final String STRENGTH_STRONG = 'Strong';
    /** Matched on name plus date of birth. Plausible, but two people can share both. */
    public static final String STRENGTH_POSSIBLE = 'Possible';

    @AuraEnabled public Id patientId;
    @AuraEnabled public String name;
    @AuraEnabled public String email;
    @AuraEnabled public String phone;
    @AuraEnabled public Date birthdate;
    @AuraEnabled public String city;
    @AuraEnabled public String strength;
    @AuraEnabled public List<String> matchReasons;
    @AuraEnabled public List<PlanSummary> existingPlans;

    /**
     * True when this patient already holds an open plan for the program on the form. Enrolling
     * again would create a second plan for the same program, which is the duplicate the
     * enrollment flow exists to prevent.
     */
    @AuraEnabled public Boolean hasPlanForRequestedProgram;

    public PatientMatchResult() {
        this.matchReasons = new List<String>();
        this.existingPlans = new List<PlanSummary>();
        this.hasPlanForRequestedProgram = false;
        this.strength = STRENGTH_POSSIBLE;
    }

    /** @description A plan the matched patient already holds, for display on the match screen. */
    public class PlanSummary {
        @AuraEnabled public Id planId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String programCode;
        @AuraEnabled public String programName;
        @AuraEnabled public String status;
        @AuraEnabled public Date enrollmentDate;
        @AuraEnabled public Boolean isOpen;
    }
}

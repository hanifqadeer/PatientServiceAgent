/**
 * @description Service for Patient Support Plan lifecycle operations.
 *              PSPs are modeled as Case records with the Patient_Support_Plan record type.
 *              Supports: create, activate, complete, discontinue, assign coordinator.
 *              Bulk-safe — no SOQL/DML in loops.
 */
public with sharing class PatientSupportPlanService {

    private static final String PSP_RT = 'Patient_Support_Plan';

    /**
     * @description Create a new Patient Support Plan (PSP Case).
     * @param patientId The patient Account Id (ContactId on Case comes from Person Account).
     * @param programId The Care Program Id to associate.
     * @param enrollmentSource How the enrollment was received.
     * @param coordinatorId The assigned care coordinator User Id (optional).
     * @return The newly inserted PSP Case.
     */
    public Case createPlan(Id patientId, Id programId, String enrollmentSource, Id coordinatorId) {
        if (patientId == null || programId == null) {
            throw new PlanServiceException('Patient and Care Program are required to create a Support Plan.');
        }

        Id pspRtId = Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get(PSP_RT)
            .getRecordTypeId();

        // Look up the PersonContactId for the Patient Account
        List<Account> patients = [
            SELECT PersonContactId FROM Account WHERE Id = :patientId LIMIT 1
        ];
        if (patients.isEmpty() || patients[0].PersonContactId == null) {
            throw new PlanServiceException('Patient account not found or is not a Person Account.');
        }

        // Get the program name for the Case Subject
        List<Care_Program__c> programs = [
            SELECT Name FROM Care_Program__c WHERE Id = :programId LIMIT 1
        ];
        String programName = programs.isEmpty() ? 'Unknown Program' : programs[0].Name;

        Case psp = new Case(
            AccountId = patientId,
            ContactId = patients[0].PersonContactId,
            Care_Program__c = programId,
            Subject = 'Patient Support Plan - ' + programName,
            Status = 'New',
            Priority = 'Medium',
            Enrollment_Source__c = enrollmentSource,
            Enrollment_Date__c = Date.today(),
            Support_Level__c = 'Standard',
            Primary_Care_Coordinator__c = coordinatorId
        );
        psp.put('RecordTypeId', pspRtId);

        insert psp;
        return psp;
    }

    /**
     * @description Activate a PSP — sets status to In Progress, records plan start date.
     * @param planId The PSP Case Id to activate.
     */
    public void activatePlan(Id planId) {
        Case psp = getPlan(planId);
        psp.Status = 'In Progress';
        psp.Plan_Start_Date__c = Date.today();
        update psp;
    }

    /**
     * @description Complete/graduate a PSP.
     * @param planId The PSP Case Id.
     * @param completionReason Reason for completion.
     */
    public void completePlan(Id planId, String completionReason) {
        Case psp = getPlan(planId);
        psp.Status = 'Closed';
        psp.Plan_End_Date__c = Date.today();
        psp.Completion_Reason__c = completionReason;
        psp.Resolution_Summary__c = 'Plan completed: ' + completionReason;
        update psp;
    }

    /**
     * @description Discontinue a PSP before normal completion.
     * @param planId The PSP Case Id.
     * @param discontinuationReason Reason for discontinuation.
     */
    public void discontinuePlan(Id planId, String discontinuationReason) {
        Case psp = getPlan(planId);
        psp.Status = 'Closed';
        psp.Plan_End_Date__c = Date.today();
        psp.Discontinuation_Reason__c = discontinuationReason;
        psp.Resolution_Summary__c = 'Plan discontinued: ' + discontinuationReason;
        update psp;
    }

    /**
     * @description Assign or reassign a care coordinator to a PSP.
     * @param planId The PSP Case Id.
     * @param coordinatorId The User Id of the coordinator.
     */
    public void assignCoordinator(Id planId, Id coordinatorId) {
        Case psp = getPlan(planId);
        psp.Primary_Care_Coordinator__c = coordinatorId;
        update psp;
    }

    /**
     * @description Create an onboarding Task for a newly activated PSP.
     * @param planId The PSP Case Id.
     * @param coordinatorId The coordinator to assign the task to.
     * @return The created onboarding Task.
     */
    public Task createOnboardingTask(Id planId, Id coordinatorId) {
        Task onboarding = new Task(
            WhatId = planId,
            OwnerId = coordinatorId != null ? coordinatorId : UserInfo.getUserId(),
            Subject = 'Complete Patient Onboarding',
            Description = 'Welcome the patient, verify information, explain program benefits and next steps.',
            Status = 'Not Started',
            Priority = 'High',
            ActivityDate = Date.today().addDays(3)
        );
        insert onboarding;
        return onboarding;
    }

    private Case getPlan(Id planId) {
        String query = 'SELECT Id, Status, Plan_Start_Date__c, Plan_End_Date__c, ' +
                       'Completion_Reason__c, Discontinuation_Reason__c, ' +
                       'Resolution_Summary__c, Primary_Care_Coordinator__c ' +
                       'FROM Case WHERE Id = :planId AND RecordType.DeveloperName = :PSP_RT LIMIT 1';
        List<Case> plans = Database.query(query);
        if (plans.isEmpty()) {
            throw new PlanServiceException('Patient Support Plan not found: ' + planId);
        }
        return plans[0];
    }

    public class PlanServiceException extends Exception {}
}

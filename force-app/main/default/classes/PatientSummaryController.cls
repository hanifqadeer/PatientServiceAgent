/**
 * @description Thin Apex controller for the Patient Summary / 360 LWC.
 *              Aggregates plan, case, task, event, and relationship data
 *              for the Care Coordinator's view.
 */
public with sharing class PatientSummaryController {

    /**
     * @description Get comprehensive patient summary data.
     * @param patientId The patient Account Id.
     * @return PatientSummaryData aggregated DTO.
     */
    @AuraEnabled
    public static PatientSummaryData getPatientSummary(Id patientId) {
        try {
            PatientSummaryData summary = new PatientSummaryData();

            // ── Patient details with Support Plans ──
            PatientService patSvc = new PatientService();
            List<Account> patients = patSvc.getPatientsWithPlans(new Set<Id>{ patientId });
            if (patients.isEmpty()) {
                throw new AuraHandledException('Patient not found.');
            }
            summary.patient = patients[0];
            summary.supportPlans = patients[0].Cases;

            // ── Recent Cases (across all plans) ──
            String caseQuery = 'SELECT Id, CaseNumber, Subject, Status, Priority, ' +
                               'Support_Category__c, CreatedDate ' + // Removed RecordType.Name for now
                               'FROM Case WHERE AccountId = :patientId ' +
                               'AND RecordType.DeveloperName != \'Patient_Support_Plan\' ' +
                               'ORDER BY CreatedDate DESC LIMIT 10';
            summary.recentCases = Database.query(caseQuery);

            // ── Recent Tasks ──
            summary.recentTasks = [
                SELECT Id, Subject, Status, Priority, ActivityDate, OwnerId, Owner.Name
                FROM Task
                WHERE AccountId = :patientId
                ORDER BY CreatedDate DESC
                LIMIT 10
            ];

            // ── Upcoming Events ──
            summary.upcomingEvents = [
                SELECT Id, Subject, StartDateTime, EndDateTime, Location, OwnerId, Owner.Name
                FROM Event
                WHERE AccountId = :patientId
                  AND StartDateTime >= :Datetime.now()
                ORDER BY StartDateTime ASC
                LIMIT 5
            ];

            // ── Related HCPs/HCOs via Affiliations ──
            summary.affiliations = [
                SELECT Id, Account_2__c, Account_2__r.Name,
                       Affiliation_Type__c, Role__c, Is_Primary__c, Status__c
                FROM Affiliation__c
                WHERE Account_1__c = :patientId
                  AND Status__c = 'Active'
                ORDER BY Is_Primary__c DESC, CreatedDate DESC
            ];

            return summary;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to load patient summary: ' + e.getMessage());
        }
    }

    /**
     * @description Get AI-generated grounded summary for a specific plan.
     * @param planId The PSP Case Id.
     * @return SupportSummaryResult with metrics and attention flags.
     */
    @AuraEnabled
    public static SupportSummaryResult getPlanSummary(Id planId) {
        try {
            AISummaryService summSvc = new AISummaryService();
            return summSvc.generateSummary(planId);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to generate plan summary: ' + e.getMessage());
        }
    }

    /**
     * @description Aggregated patient summary data DTO.
     */
    public class PatientSummaryData {
        @AuraEnabled public Account patient;
        @AuraEnabled public List<Case> supportPlans;
        @AuraEnabled public List<Case> recentCases;
        @AuraEnabled public List<Task> recentTasks;
        @AuraEnabled public List<Event> upcomingEvents;
        @AuraEnabled public List<Affiliation__c> affiliations;
    }
}

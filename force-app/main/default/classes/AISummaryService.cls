/**
 * @description Generates grounded patient support summaries from trusted data.
 *              Deterministic — no LLM involved. Formats Plan, Case, Task, and Event
 *              data into a structured readable summary with attention flags.
 *
 *              Per architecture: "Ground summaries in trusted data.
 *              Do not provide diagnosis/prescribing/clinical decision support."
 */
public with sharing class AISummaryService {

    /**
     * @description Generate a grounded support summary for a Patient Support Plan.
     * @param planId The PSP Case Id.
     * @return SupportSummaryResult with summary text, metrics, and flags.
     */
    public SupportSummaryResult generateSummary(Id planId) {
        if (planId == null) {
            throw new SummaryServiceException('Plan Id is required.');
        }

        SupportSummaryResult result = new SupportSummaryResult();

        // ── Get Plan details ──
        String query = 'SELECT Id, Subject, Status, Priority, ' +
                       'Care_Program__c, Care_Program__r.Name, ' +
                       'Primary_Care_Coordinator__c, Primary_Care_Coordinator__r.Name, ' +
                       'Last_Review_Date__c, Next_Review_Date__c, ' +
                       'Plan_Start_Date__c, Enrollment_Date__c, Support_Level__c ' +
                       'FROM Case WHERE Id = :planId ' +
                       'AND RecordType.DeveloperName = \'Patient_Support_Plan\' LIMIT 1';
        List<Case> plans = Database.query(query);

        if (plans.isEmpty()) {
            throw new SummaryServiceException('Patient Support Plan not found.');
        }

        Case plan = plans[0];
        result.planStatus = plan.Status;
        result.careProgramName = plan.Care_Program__r?.Name;
        result.coordinatorName = plan.Primary_Care_Coordinator__r?.Name;
        result.lastReviewDate = plan.Last_Review_Date__c;
        result.nextReviewDate = plan.Next_Review_Date__c;

        // ── Count open child cases ──
        List<AggregateResult> caseAgg = [
            SELECT COUNT(Id) cnt
            FROM Case
            WHERE ParentId = :planId
              AND IsClosed = false
        ];
        result.openCasesCount = (Integer) caseAgg[0].get('cnt');

        // ── Count overdue tasks ──
        List<AggregateResult> taskAgg = [
            SELECT COUNT(Id) cnt
            FROM Task
            WHERE WhatId = :planId
              AND IsClosed = false
              AND ActivityDate < TODAY
        ];
        result.overdueTasks = (Integer) taskAgg[0].get('cnt');

        // ── Get next scheduled event ──
        List<Event> nextEvents = [
            SELECT StartDateTime
            FROM Event
            WHERE WhatId = :planId
              AND StartDateTime >= :Datetime.now()
            ORDER BY StartDateTime ASC
            LIMIT 1
        ];
        if (!nextEvents.isEmpty()) {
            result.nextScheduledEvent = nextEvents[0].StartDateTime.date();
        }

        // ── Build attention flags ──
        if (result.overdueTasks > 0) {
            result.attentionFlags.add(result.overdueTasks + ' overdue task(s) require attention.');
        }
        if (result.openCasesCount > 5) {
            result.attentionFlags.add('High number of open cases (' + result.openCasesCount + ').');
        }
        if (plan.Next_Review_Date__c != null && plan.Next_Review_Date__c <= Date.today()) {
            result.attentionFlags.add('Plan review is overdue (due ' + plan.Next_Review_Date__c.format() + ').');
        }

        // ── Build summary text ──
        List<String> summaryParts = new List<String>();
        summaryParts.add('Patient Support Plan: ' + plan.Subject);
        summaryParts.add('Program: ' + (result.careProgramName != null ? result.careProgramName : 'N/A'));
        summaryParts.add('Status: ' + plan.Status + ' | Support Level: ' + plan.Support_Level__c);
        summaryParts.add('Coordinator: ' + (result.coordinatorName != null ? result.coordinatorName : 'Unassigned'));
        summaryParts.add('Open Cases: ' + result.openCasesCount + ' | Overdue Tasks: ' + result.overdueTasks);
        if (result.nextScheduledEvent != null) {
            summaryParts.add('Next Scheduled Event: ' + result.nextScheduledEvent.format());
        }
        if (!result.attentionFlags.isEmpty()) {
            summaryParts.add('⚠ Attention: ' + String.join(result.attentionFlags, ' '));
        }

        result.summaryText = String.join(summaryParts, '\n');

        return result;
    }

    public class SummaryServiceException extends Exception {}
}

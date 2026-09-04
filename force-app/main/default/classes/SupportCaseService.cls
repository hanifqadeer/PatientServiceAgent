/**
 * @description Service for Support Case operations.
 *              Creates cases linked to Parent PSP Cases via ParentId.
 *              Handles routing by category, escalation, and closure with summary.
 *              Bulk-safe, runs with sharing.
 */
public with sharing class SupportCaseService {

    // Record type mapping: Support_Category__c → Record Type Developer Name
    private static final Map<String, String> CATEGORY_TO_RT = new Map<String, String>{
        'Benefits Verification' => 'Access_Reimbursement',
        'Prior Authorization' => 'Access_Reimbursement',
        'Appeals' => 'Access_Reimbursement',
        'Reimbursement' => 'Access_Reimbursement',
        'Education' => 'Patient_Support',
        'Program Question' => 'Patient_Support',
        'General Assistance' => 'Patient_Support',
        'Appointment' => 'Coordination',
        'Site of Care' => 'Coordination',
        'Provider Coordination' => 'Coordination'
    };

    /**
     * @description Create a new support Case as a child of a PSP Case.
     * @param parentPlanId The parent PSP Case Id.
     * @param category The Support_Category__c value.
     * @param subject Case subject.
     * @param description Case description.
     * @param priority Case priority (High, Medium, Low).
     * @return The newly inserted Case.
     */
    public Case createSupportCase(Id parentPlanId, String category, String subject,
                                   String description, String priority) {
        if (parentPlanId == null) {
            throw new CaseServiceException('Parent Support Plan is required.');
        }
        if (String.isBlank(category)) {
            throw new CaseServiceException('Support Category is required.');
        }

        String rtDeveloperName = CATEGORY_TO_RT.get(category);
        if (rtDeveloperName == null) {
            throw new CaseServiceException('Unknown support category: ' + category);
        }

        Id rtId = Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get(rtDeveloperName)
            .getRecordTypeId();

        // Get parent plan info for AccountId/ContactId propagation
        List<Case> parents = [
            SELECT AccountId, ContactId FROM Case WHERE Id = :parentPlanId LIMIT 1
        ];
        if (parents.isEmpty()) {
            throw new CaseServiceException('Parent Support Plan not found.');
        }

        Case supportCase = new Case(
            ParentId = parentPlanId,
            AccountId = parents[0].AccountId,
            ContactId = parents[0].ContactId,
            Subject = subject,
            Description = description,
            Status = 'New',
            Priority = String.isNotBlank(priority) ? priority : 'Medium',
            Support_Category__c = category
        );
        supportCase.put('RecordTypeId', rtId);

        insert supportCase;
        return supportCase;
    }

    /**
     * @description Escalate a Case — sets priority to High and status to In Progress.
     * @param caseId The Case Id to escalate.
     * @param reason Description of why the case is being escalated.
     */
    public void escalateCase(Id caseId, String reason) {
        Case c = [SELECT Id, Priority, Status, Description FROM Case WHERE Id = :caseId LIMIT 1];
        c.Priority = 'High';
        if (c.Status == 'New') {
            c.Status = 'In Progress';
        }
        c.Description = (String.isNotBlank(c.Description) ? c.Description + '\n\n' : '')
                       + '[ESCALATED] ' + reason;
        update c;
    }

    /**
     * @description Resolve and close a Case with a resolution summary.
     * @param caseId The Case Id.
     * @param resolutionSummary Summary of the resolution.
     */
    public void resolveCase(Id caseId, String resolutionSummary) {
        if (String.isBlank(resolutionSummary)) {
            throw new CaseServiceException('Resolution summary is required to close a case.');
        }
        Case c = [SELECT Id, Status FROM Case WHERE Id = :caseId LIMIT 1];
        c.Status = 'Closed';
        c.Resolution_Summary__c = resolutionSummary;
        update c;
    }

    /**
     * @description Get all child cases for a given PSP (parent case).
     * @param parentPlanId The parent PSP Case Id.
     * @return List of child support cases.
     */
    public List<Case> getCasesForPlan(Id parentPlanId) {
        return [
            SELECT Id, CaseNumber, Subject, Status, Priority,
                   Support_Category__c, Support_Subcategory__c,
                   CreatedDate, ClosedDate, Resolution_Summary__c
            FROM Case
            WHERE ParentId = :parentPlanId
            ORDER BY CreatedDate DESC
        ];
    }

    public class CaseServiceException extends Exception {}
}

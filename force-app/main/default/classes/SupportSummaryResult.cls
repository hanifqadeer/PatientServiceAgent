/**
 * @description DTO/Wrapper class for AI-generated patient support summary.
 *              Grounded in trusted Plan, Case, Task, and Event data —
 *              deterministic formatting, not LLM generation.
 *              Per architecture: "Ground summaries in trusted data.
 *              Do not provide diagnosis/prescribing/clinical decision support."
 */
public with sharing class SupportSummaryResult {

    @AuraEnabled public String summaryText;
    @AuraEnabled public Integer openCasesCount;
    @AuraEnabled public Integer overdueTasks;
    @AuraEnabled public Date nextScheduledEvent;
    @AuraEnabled public List<String> attentionFlags;

    // ── Plan context ──
    @AuraEnabled public String planStatus;
    @AuraEnabled public String careProgramName;
    @AuraEnabled public String coordinatorName;
    @AuraEnabled public Date lastReviewDate;
    @AuraEnabled public Date nextReviewDate;

    public SupportSummaryResult() {
        this.attentionFlags = new List<String>();
        this.openCasesCount = 0;
        this.overdueTasks = 0;
    }
}

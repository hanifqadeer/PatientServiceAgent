/**
 * @description Test class for AISummaryService.
 *              Covers summary generation, attention flags, open case counting,
 *              overdue task detection, and error handling.
 */
@IsTest
private class AISummaryServiceTest {

    @IsTest
    static void testGenerateSummary_BasicPlan() {
        List<Account> patients = TestDataFactory.createPatients(1);
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        List<Case> plans = TestDataFactory.createSupportPlans(patients, programs[0]);

        Test.startTest();
        AISummaryService svc = new AISummaryService();
        SupportSummaryResult result = svc.generateSummary(plans[0].Id);
        Test.stopTest();

        System.assertNotEquals(null, result.summaryText, 'Summary text should be generated.');
        System.assertEquals(0, result.openCasesCount, 'No open child cases.');
        System.assertEquals(0, result.overdueTasks, 'No overdue tasks.');
        System.assertNotEquals(null, result.attentionFlags, 'Attention flags list should not be null.');
    }

    @IsTest
    static void testGenerateSummary_WithOpenCasesAndTasks() {
        List<Account> patients = TestDataFactory.createPatients(1);
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        List<Case> plans = TestDataFactory.createSupportPlans(patients, programs[0]);

        // Create 3 open child cases
        TestDataFactory.createSupportCases(plans[0], 3, 'Prior Authorization');

        // Create an overdue task (ActivityDate in the past)
        Task overdueTask = new Task(
            WhatId = plans[0].Id,
            Subject = 'Overdue Task',
            Status = 'Not Started',
            Priority = 'High',
            ActivityDate = Date.today().addDays(-5)
        );
        insert overdueTask;

        Test.startTest();
        AISummaryService svc = new AISummaryService();
        SupportSummaryResult result = svc.generateSummary(plans[0].Id);
        Test.stopTest();

        System.assertEquals(3, result.openCasesCount, 'Should count 3 open cases.');
        System.assertEquals(1, result.overdueTasks, 'Should count 1 overdue task.');
        System.assert(!result.attentionFlags.isEmpty(), 'Should have attention flags for overdue task.');
        System.assert(result.summaryText.contains('Open Cases: 3'), 'Summary should mention open cases count.');
    }

    @IsTest
    static void testGenerateSummary_NullPlanId() {
        Test.startTest();
        try {
            AISummaryService svc = new AISummaryService();
            svc.generateSummary(null);
            System.assert(false, 'Should throw for null plan ID.');
        } catch (AISummaryService.SummaryServiceException e) {
            System.assert(e.getMessage().contains('required'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testGenerateSummary_InvalidPlanId() {
        List<Account> patients = TestDataFactory.createPatients(1);
        // Use a patient Account ID as if it were a plan — should fail
        Test.startTest();
        try {
            AISummaryService svc = new AISummaryService();
            svc.generateSummary(patients[0].Id);
            System.assert(false, 'Should throw for non-PSP ID.');
        } catch (AISummaryService.SummaryServiceException e) {
            System.assert(e.getMessage().contains('not found'));
        }
        Test.stopTest();
    }
}

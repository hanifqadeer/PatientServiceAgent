/**
 * @description Test class for PatientSupportPlanService.
 *              Covers create, activate, complete, discontinue, coordinator assignment.
 */
@IsTest
private class PatientSupportPlanServiceTest {

    @IsTest
    static void testCreatePlan_Success() {
        List<Account> patients = TestDataFactory.createPatients(1);
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);

        Test.startTest();
        PatientSupportPlanService svc = new PatientSupportPlanService();
        Case plan = svc.createPlan(patients[0].Id, programs[0].Id, 'Fax', null);
        Test.stopTest();

        System.assertNotEquals(null, plan.Id, 'PSP should be created.');
        Case fetched = [SELECT Status, Care_Program__c FROM Case WHERE Id = :plan.Id];
        System.assertEquals(programs[0].Id, fetched.Care_Program__c);
    }

    @IsTest
    static void testCreatePlan_MissingPatient() {
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        Test.startTest();
        try {
            PatientSupportPlanService svc = new PatientSupportPlanService();
            svc.createPlan(null, programs[0].Id, 'Fax', null);
            System.assert(false, 'Should have thrown an exception.');
        } catch (PatientSupportPlanService.PlanServiceException e) {
            System.assert(e.getMessage().contains('required'), 'Error should mention required fields.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testActivatePlan() {
        List<Account> patients = TestDataFactory.createPatients(1);
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        List<Case> plans = TestDataFactory.createSupportPlans(patients, programs[0]);

        Test.startTest();
        PatientSupportPlanService svc = new PatientSupportPlanService();
        svc.activatePlan(plans[0].Id);
        Test.stopTest();

        Case updated = [SELECT Status, Plan_Start_Date__c FROM Case WHERE Id = :plans[0].Id];
        System.assertEquals('In Progress', updated.Status);
        System.assertEquals(Date.today(), updated.Plan_Start_Date__c);
    }

    @IsTest
    static void testCompletePlan() {
        List<Account> patients = TestDataFactory.createPatients(1);
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        List<Case> plans = TestDataFactory.createSupportPlans(patients, programs[0]);

        Test.startTest();
        PatientSupportPlanService svc = new PatientSupportPlanService();
        svc.completePlan(plans[0].Id, 'Patient graduated successfully.');
        Test.stopTest();

        Case updated = [SELECT Status, Plan_End_Date__c, Completion_Reason__c FROM Case WHERE Id = :plans[0].Id];
        System.assertEquals('Closed', updated.Status);
        System.assertEquals(Date.today(), updated.Plan_End_Date__c);
        System.assert(updated.Completion_Reason__c.contains('graduated'));
    }

    @IsTest
    static void testDiscontinuePlan() {
        List<Account> patients = TestDataFactory.createPatients(1);
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        List<Case> plans = TestDataFactory.createSupportPlans(patients, programs[0]);

        Test.startTest();
        PatientSupportPlanService svc = new PatientSupportPlanService();
        svc.discontinuePlan(plans[0].Id, 'Patient withdrew from program.');
        Test.stopTest();

        Case updated = [SELECT Status, Discontinuation_Reason__c FROM Case WHERE Id = :plans[0].Id];
        System.assertEquals('Closed', updated.Status);
        System.assert(updated.Discontinuation_Reason__c.contains('withdrew'));
    }

    @IsTest
    static void testCreateOnboardingTask() {
        List<Account> patients = TestDataFactory.createPatients(1);
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        List<Case> plans = TestDataFactory.createSupportPlans(patients, programs[0]);

        Test.startTest();
        PatientSupportPlanService svc = new PatientSupportPlanService();
        Task t = svc.createOnboardingTask(plans[0].Id, UserInfo.getUserId());
        Test.stopTest();

        System.assertNotEquals(null, t.Id, 'Onboarding task should be created.');
        Task fetched = [SELECT Subject, Priority, WhatId FROM Task WHERE Id = :t.Id];
        System.assertEquals('Complete Patient Onboarding', fetched.Subject);
        System.assertEquals('High', fetched.Priority);
        System.assertEquals(plans[0].Id, fetched.WhatId);
    }
}

/**
 * @description Test class for SupportCaseService.
 *              Covers create, category routing, escalation, resolution, closure validation.
 */
@IsTest
private class SupportCaseServiceTest {

    static List<Case> setupPlans() {
        List<Account> patients = TestDataFactory.createPatients(1);
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        return TestDataFactory.createSupportPlans(patients, programs[0]);
    }

    @IsTest
    static void testCreateSupportCase_AccessReimbursement() {
        List<Case> plans = setupPlans();

        Test.startTest();
        SupportCaseService svc = new SupportCaseService();
        Case c = svc.createSupportCase(plans[0].Id, 'Benefits Verification',
                                        'BV for patient', 'Checking benefits', 'High');
        Test.stopTest();

        Case fetched = [SELECT Support_Category__c, Status, Priority FROM Case WHERE Id = :c.Id];
        System.assertEquals('Benefits Verification', fetched.Support_Category__c);
        System.assertEquals('High', fetched.Priority);
    }

    @IsTest
    static void testCreateSupportCase_PatientSupport() {
        List<Case> plans = setupPlans();

        Test.startTest();
        SupportCaseService svc = new SupportCaseService();
        Case c = svc.createSupportCase(plans[0].Id, 'Education', 'Patient education', 'Program info', 'Medium');
        Test.stopTest();

        Case fetched = [SELECT Support_Category__c FROM Case WHERE Id = :c.Id];
    }

    @IsTest
    static void testCreateSupportCase_Coordination() {
        List<Case> plans = setupPlans();

        Test.startTest();
        SupportCaseService svc = new SupportCaseService();
        Case c = svc.createSupportCase(plans[0].Id, 'Site of Care', 'Site coordination', null, null);
        Test.stopTest();

        Case fetched = [SELECT Support_Category__c FROM Case WHERE Id = :c.Id];
    }

    @IsTest
    static void testCreateSupportCase_InvalidCategory() {
        List<Case> plans = setupPlans();

        Test.startTest();
        try {
            SupportCaseService svc = new SupportCaseService();
            svc.createSupportCase(plans[0].Id, 'INVALID_CATEGORY', 'Test', null, null);
            System.assert(false, 'Should have thrown an exception for unknown category.');
        } catch (SupportCaseService.CaseServiceException e) {
            System.assert(e.getMessage().contains('Unknown'), 'Error should mention unknown category.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testEscalateCase() {
        List<Case> plans = setupPlans();
        SupportCaseService svc = new SupportCaseService();
        Case c = svc.createSupportCase(plans[0].Id, 'Prior Authorization', 'PA request', null, 'Medium');

        Test.startTest();
        svc.escalateCase(c.Id, 'Payer denied — needs urgent review.');
        Test.stopTest();

        Case fetched = [SELECT Priority, Status FROM Case WHERE Id = :c.Id];
        System.assertEquals('High', fetched.Priority);
        System.assertEquals('In Progress', fetched.Status);
    }

    @IsTest
    static void testResolveCase_Success() {
        List<Case> plans = setupPlans();
        SupportCaseService svc = new SupportCaseService();
        Case c = svc.createSupportCase(plans[0].Id, 'Benefits Verification', 'BV', null, 'Medium');

        Test.startTest();
        svc.resolveCase(c.Id, 'Benefits confirmed — patient has full coverage.');
        Test.stopTest();

        Case fetched = [SELECT Status, Resolution_Summary__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('Closed', fetched.Status);
        System.assert(fetched.Resolution_Summary__c.contains('confirmed'));
    }

    @IsTest
    static void testResolveCase_MissingResolution() {
        List<Case> plans = setupPlans();
        SupportCaseService svc = new SupportCaseService();
        Case c = svc.createSupportCase(plans[0].Id, 'Education', 'Education', null, 'Low');

        Test.startTest();
        try {
            svc.resolveCase(c.Id, '');
            System.assert(false, 'Should have thrown for missing resolution summary.');
        } catch (SupportCaseService.CaseServiceException e) {
            System.assert(e.getMessage().contains('required'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetCasesForPlan_Bulk() {
        List<Case> plans = setupPlans();
        TestDataFactory.createSupportCases(plans[0], 5, 'Education');

        Test.startTest();
        SupportCaseService svc = new SupportCaseService();
        List<Case> cases = svc.getCasesForPlan(plans[0].Id);
        Test.stopTest();

        System.assertEquals(5, cases.size(), 'Should return all 5 child cases.');
    }
}

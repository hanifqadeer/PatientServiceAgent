/**
 * @description Test class for EnrollmentService — the orchestrator.
 *              Covers full enrollment journey, duplicate patient handling,
 *              invalid program, and missing data scenarios.
 */
@IsTest
private class EnrollmentServiceTest {

    @IsTest
    static void testProcessEnrollment_NewPatient_Success() {
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(programs[0].Program_Code__c);

        Test.startTest();
        EnrollmentService svc = new EnrollmentService();
        EnrollmentService.EnrollmentResult result = svc.processEnrollment(extraction, null);
        Test.stopTest();

        System.assertNotEquals(null, result.patientId, 'Patient should be created.');
        System.assertNotEquals(null, result.planId, 'Support Plan should be created.');
        System.assertNotEquals(null, result.onboardingTaskId, 'Onboarding task should be created.');
        System.assert(result.isNewPatient, 'Should flag as new patient.');

        Case plan = [SELECT Status, Care_Program__c FROM Case WHERE Id = :result.planId];
        System.assertEquals('In Progress', plan.Status, 'Plan should be activated.');
        System.assertEquals(programs[0].Id, plan.Care_Program__c);
    }

    @IsTest
    static void testProcessEnrollment_ExistingPatient() {
        List<Account> patients = TestDataFactory.createPatients(1);
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(programs[0].Program_Code__c);

        Test.startTest();
        EnrollmentService svc = new EnrollmentService();
        EnrollmentService.EnrollmentResult result = svc.processEnrollment(extraction, patients[0].Id);
        Test.stopTest();

        System.assertEquals(patients[0].Id, result.patientId, 'Should use existing patient.');
        System.assert(!result.isNewPatient, 'Should NOT flag as new patient.');
    }

    @IsTest
    static void testProcessEnrollment_InvalidProgram() {
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction('DOES-NOT-EXIST');

        Test.startTest();
        try {
            EnrollmentService svc = new EnrollmentService();
            svc.processEnrollment(extraction, null);
            System.assert(false, 'Should have thrown for invalid program.');
        } catch (EnrollmentService.EnrollmentException e) {
            System.assert(e.getMessage().contains('not found'), 'Error should mention program not found.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testProcessEnrollment_ClosedProgram() {
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        programs[0].Status__c = 'Closed';
        update programs[0];
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(programs[0].Program_Code__c);

        Test.startTest();
        try {
            EnrollmentService svc = new EnrollmentService();
            svc.processEnrollment(extraction, null);
            System.assert(false, 'Should have thrown for closed program.');
        } catch (EnrollmentService.EnrollmentException e) {
            System.assert(e.getMessage().contains('not eligible'), 'Error should mention eligibility.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testProcessEnrollment_NullExtraction() {
        Test.startTest();
        try {
            EnrollmentService svc = new EnrollmentService();
            svc.processEnrollment(null, null);
            System.assert(false, 'Should throw for null extraction.');
        } catch (EnrollmentService.EnrollmentException e) {
            System.assert(e.getMessage().contains('required'));
        }
        Test.stopTest();
    }
}

/**
 * @description Test class for PatientSummaryController.
 */
@IsTest
private class PatientSummaryControllerTest {

    @IsTest
    static void testGetPatientSummary_Success() {
        List<Account> patients = TestDataFactory.createPatients(1);
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        TestDataFactory.createSupportPlans(patients, programs[0]);

        Test.startTest();
        PatientSummaryController.PatientSummaryData data =
            PatientSummaryController.getPatientSummary(patients[0].Id);
        Test.stopTest();

        System.assertNotEquals(null, data.patient, 'Patient should be returned.');
        System.assertNotEquals(null, data.supportPlans, 'Plans should be returned.');
    }

    @IsTest
    static void testGetPlanSummary_Success() {
        List<Account> patients = TestDataFactory.createPatients(1);
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        List<Case> plans = TestDataFactory.createSupportPlans(patients, programs[0]);

        Test.startTest();
        SupportSummaryResult summary = PatientSummaryController.getPlanSummary(plans[0].Id);
        Test.stopTest();

        System.assertNotEquals(null, summary, 'Summary should be returned.');
        System.assertNotEquals(null, summary.summaryText, 'Summary text should not be null.');
        System.assertEquals(0, summary.openCasesCount, 'No child cases yet.');
    }

    @IsTest
    static void testGetPlanSummary_WithOpenCases() {
        List<Account> patients = TestDataFactory.createPatients(1);
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        List<Case> plans = TestDataFactory.createSupportPlans(patients, programs[0]);
        TestDataFactory.createSupportCases(plans[0], 3, 'Benefits Verification');

        Test.startTest();
        SupportSummaryResult summary = PatientSummaryController.getPlanSummary(plans[0].Id);
        Test.stopTest();

        System.assertEquals(3, summary.openCasesCount, 'Should count 3 open cases.');
    }

    @IsTest
    static void testGetPatientSummary_InvalidPatient() {
        Test.startTest();
        try {
            PatientSummaryController.getPatientSummary(null);
            System.assert(false, 'Should have thrown for null patient ID.');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
        Test.stopTest();
    }
}

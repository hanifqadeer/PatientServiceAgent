/**
 * @description Test class for EnrollmentController @AuraEnabled methods.
 *              Covers controller-level coverage for the enrollment LWC.
 */
@IsTest
private class EnrollmentControllerTest {

    @IsTest
    static void testGetActivePrograms() {
        TestDataFactory.createCarePrograms(2);

        Test.startTest();
        List<Care_Program__c> programs = EnrollmentController.getActivePrograms();
        Test.stopTest();

        System.assertEquals(2, programs.size(), 'Should return 2 active programs.');
    }

    @IsTest
    static void testSearchDuplicatePatients_Found() {
        List<Account> patients = TestDataFactory.createPatients(1);
        Account p = patients[0];

        Test.startTest();
        List<Account> dupes = EnrollmentController.searchDuplicatePatients(
            p.FirstName, p.LastName, p.PersonBirthdate);
        Test.stopTest();

        System.assert(!dupes.isEmpty(), 'Should find the duplicate patient.');
    }

    @IsTest
    static void testSearchDuplicatePatients_NotFound() {
        Test.startTest();
        List<Account> dupes = EnrollmentController.searchDuplicatePatients(
            'Ghost', 'Nobody', Date.newInstance(1800, 1, 1));
        Test.stopTest();

        System.assert(dupes.isEmpty(), 'Should find no duplicates.');
    }

    @IsTest
    static void testConfirmEnrollment_Success() {
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(programs[0].Program_Code__c);
        String extractionJson = JSON.serialize(extraction);

        Test.startTest();
        EnrollmentService.EnrollmentResult result = EnrollmentController.confirmEnrollment(
            extractionJson, null, null);
        Test.stopTest();

        System.assertNotEquals(null, result.patientId);
        System.assertNotEquals(null, result.planId);
        System.assert(result.isNewPatient);
    }

    @IsTest
    static void testConfirmEnrollment_InvalidProgram() {
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction('INVALID-CODE');
        String extractionJson = JSON.serialize(extraction);

        Test.startTest();
        try {
            EnrollmentController.confirmEnrollment(extractionJson, null, null);
            System.assert(false, 'Should have thrown AuraHandledException.');
        } catch (AuraHandledException e) {
            // Without setMessage() on the controller side this reads "Script-thrown exception"
            // and the browser shows the specialist nothing useful.
            System.assert(
                e.getMessage().contains('INVALID-CODE'),
                'The real reason must survive to the browser. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }
}

/**
 * @description Test class for PatientService — covers positive, negative,
 *              duplicate detection, and patient creation scenarios.
 */
@IsTest
private class PatientServiceTest {

    @IsTest
    static void testFindDuplicates_PositiveMatch() {
        List<Account> patients = TestDataFactory.createPatients(1);
        Account p = patients[0];

        Test.startTest();
        PatientService svc = new PatientService();
        List<Account> dupes = svc.findDuplicates(p.FirstName, p.LastName, p.PersonBirthdate);
        Test.stopTest();

        System.assert(!dupes.isEmpty(), 'Should find the patient as a duplicate match.');
    }

    @IsTest
    static void testFindDuplicates_NoMatch() {
        Test.startTest();
        PatientService svc = new PatientService();
        List<Account> dupes = svc.findDuplicates('Nonexistent', 'Person', Date.newInstance(1900, 1, 1));
        Test.stopTest();

        System.assert(dupes.isEmpty(), 'Should not find any duplicates.');
    }

    @IsTest
    static void testCreatePatient_Success() {
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(programs[0].Program_Code__c);

        Test.startTest();
        PatientService svc = new PatientService();
        Account patient = svc.createPatient(extraction);
        Test.stopTest();

        System.assertNotEquals(null, patient.Id, 'Patient should be created.');
        Account fetched = [SELECT FirstName, LastName FROM Account WHERE Id = :patient.Id];
        System.assertEquals(extraction.firstName, fetched.FirstName);
        System.assertEquals(extraction.lastName, fetched.LastName);
    }

    @IsTest
    static void testCreatePatient_MissingLastName() {
        EnrollmentExtractionResult extraction = new EnrollmentExtractionResult();
        extraction.firstName = 'Test';
        // lastName is blank

        Test.startTest();
        try {
            PatientService svc = new PatientService();
            svc.createPatient(extraction);
            System.assert(false, 'Should have thrown exception for missing last name.');
        } catch (PatientService.PatientServiceException e) {
            System.assert(e.getMessage().contains('last name'), 'Error should mention last name.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetPatients() {
        List<Account> patients = TestDataFactory.createPatients(3);
        Set<Id> ids = new Set<Id>();
        for (Account p : patients) { ids.add(p.Id); }

        Test.startTest();
        PatientService svc = new PatientService();
        List<Account> result = svc.getPatients(ids);
        Test.stopTest();

        System.assertEquals(3, result.size(), 'Should return all 3 patients.');
    }
}

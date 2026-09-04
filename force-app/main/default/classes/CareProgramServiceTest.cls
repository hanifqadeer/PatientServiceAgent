/**
 * @description Test class for CareProgramService — active programs, eligibility validation.
 */
@IsTest
private class CareProgramServiceTest {

    @IsTest
    static void testGetActivePrograms() {
        TestDataFactory.createCarePrograms(3);

        Test.startTest();
        CareProgramService svc = new CareProgramService();
        List<Care_Program__c> active = svc.getActivePrograms();
        Test.stopTest();

        System.assertEquals(3, active.size(), 'Should return all 3 active programs.');
    }

    @IsTest
    static void testGetProgramByCode_Found() {
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);

        Test.startTest();
        CareProgramService svc = new CareProgramService();
        Care_Program__c found = svc.getProgramByCode(programs[0].Program_Code__c);
        Test.stopTest();

        System.assertNotEquals(null, found, 'Should find the program.');
        System.assertEquals(programs[0].Id, found.Id);
    }

    @IsTest
    static void testGetProgramByCode_NotFound() {
        Test.startTest();
        CareProgramService svc = new CareProgramService();
        Care_Program__c found = svc.getProgramByCode('NONEXISTENT');
        Test.stopTest();

        System.assertEquals(null, found, 'Should return null for nonexistent code.');
    }

    @IsTest
    static void testIsProgramEligible_Active() {
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);

        Test.startTest();
        CareProgramService svc = new CareProgramService();
        Boolean eligible = svc.isProgramEligible(programs[0].Id);
        Test.stopTest();

        System.assert(eligible, 'Active program within date range should be eligible.');
    }

    @IsTest
    static void testIsProgramEligible_Closed() {
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(1);
        programs[0].Status__c = 'Closed';
        update programs[0];

        Test.startTest();
        CareProgramService svc = new CareProgramService();
        Boolean eligible = svc.isProgramEligible(programs[0].Id);
        Test.stopTest();

        System.assert(!eligible, 'Closed program should not be eligible.');
    }
}

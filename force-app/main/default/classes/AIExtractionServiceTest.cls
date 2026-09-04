/**
 * @description Test class for AIExtractionService and AIExtractionMock.
 *              Covers complete extraction, incomplete extraction, and error handling.
 */
@IsTest
private class AIExtractionServiceTest {

    @IsTest
    static void testGetMockExtraction_Complete() {
        Test.startTest();
        EnrollmentExtractionResult result = AIExtractionMock.getMockExtraction();
        Test.stopTest();

        System.assert(result.isComplete, 'Mock extraction should be complete.');
        System.assertEquals('Sarah', result.firstName);
        System.assertEquals('Johnson', result.lastName);
        System.assertNotEquals(null, result.dateOfBirth);
        System.assert(result.patientConfidence >= 0.9, 'Patient confidence should be high.');
        System.assert(!result.warnings.isEmpty(), 'Should have at least one warning for demo.');
    }

    @IsTest
    static void testGetIncompleteExtraction() {
        Test.startTest();
        EnrollmentExtractionResult result = AIExtractionMock.getIncompleteExtraction();
        Test.stopTest();

        System.assert(!result.isComplete, 'Incomplete extraction should be flagged as incomplete.');
        System.assert(result.patientConfidence < 0.5, 'Confidence should be low.');
        System.assert(result.warnings.size() >= 3, 'Should have multiple warnings.');
    }

    @IsTest
    static void testAIExtractionService_ExtractFromDocument() {
        Test.startTest();
        // documentId can be null for mock — AIExtractionService delegates to mock
        AIExtractionService svc = new AIExtractionService();
        EnrollmentExtractionResult result = svc.extractEnrollmentData(null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a result even with null documentId (mock).');
        System.assertEquals('Johnson', result.lastName);
    }

    @IsTest
    static void testExtractionResult_Defaults() {
        Test.startTest();
        EnrollmentExtractionResult result = new EnrollmentExtractionResult();
        Test.stopTest();

        System.assertEquals(false, result.isComplete);
        System.assertEquals(0.0, result.patientConfidence);
        System.assertNotEquals(null, result.warnings);
        System.assertEquals(0, result.warnings.size());
    }
}

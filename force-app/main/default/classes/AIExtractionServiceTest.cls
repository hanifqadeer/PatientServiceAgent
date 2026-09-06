/**
 * @description Tests for AIExtractionService.
 *
 *              ConnectApi.EinsteinLLM cannot be mocked with Test.setMock and is not callable
 *              in a test context, so PromptTemplateService is subclassed and injected. That
 *              stub also lets the tests assert on what was *sent* to the template — the
 *              program catalog grounding is the part most likely to regress silently.
 *
 *              Also covers AIExtractionMock, which is retained for demos and fixtures.
 */
@IsTest
private class AIExtractionServiceTest {
    /** Stands in for the Connect API call and records what it was asked to generate. */
    private class StubPromptService extends PromptTemplateService {
        public String responseText;
        public Exception failure;
        public String capturedTemplateName;
        public Map<String, ConnectApi.WrappedValue> capturedInputs;

        public override String generate(
            String templateApiName,
            Map<String, ConnectApi.WrappedValue> inputParams
        ) {
            this.capturedTemplateName = templateApiName;
            this.capturedInputs = inputParams;
            if (failure != null) {
                throw failure;
            }
            return responseText;
        }
    }

    private static Id createFile(String pathOnClient, String body) {
        ContentVersion version = new ContentVersion(
            Title = 'Enrollment Form',
            PathOnClient = pathOnClient,
            VersionData = Blob.valueOf(body),
            IsMajorVersion = true
        );
        insert version;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
    }

    private static String minimalGeneration() {
        return '{"documentType":"enrollment form",' +
            '"patient":{"lastName":"Johnson","firstName":"Sarah","confidence":0.9},' +
            '"program":{"programCode":"ONCO-HUB-001","confidence":0.9},' +
            '"warnings":[]}';
    }

    private static AIExtractionService serviceWith(StubPromptService stub) {
        AIExtractionService service = new AIExtractionService();
        service.promptService = stub;
        return service;
    }

    @IsTest
    static void extractsFromAnUploadedPdf() {
        Id documentId = createFile('enrollment-form.pdf', '%PDF-1.4 sample');
        StubPromptService stub = new StubPromptService();
        stub.responseText = minimalGeneration();

        Test.startTest();
        EnrollmentExtractionResult result = serviceWith(stub).extractEnrollmentData(documentId);
        Test.stopTest();

        System.assertEquals('Johnson', result.lastName, 'The generated data should reach the DTO.');
        System.assertEquals(
            'Enrollment_Document_Extraction',
            stub.capturedTemplateName,
            'The service should invoke the enrollment extraction template.'
        );
    }

    @IsTest
    static void passesTheContentDocumentIdAsTheFileInput() {
        Id documentId = createFile('enrollment-form.pdf', '%PDF-1.4 sample');
        StubPromptService stub = new StubPromptService();
        stub.responseText = minimalGeneration();

        Test.startTest();
        serviceWith(stub).extractEnrollmentData(documentId);
        Test.stopTest();

        System.assert(
            stub.capturedInputs.containsKey('Input:enrollmentDocument'),
            'The file input must be present or the model has nothing to read.'
        );
        Map<String, String> fileValue = (Map<String, String>) stub.capturedInputs
            .get('Input:enrollmentDocument')
            .value;
        System.assertEquals(
            String.valueOf(documentId),
            fileValue.get('id'),
            'A File input takes the ContentDocument id, not the ContentVersion id.'
        );
    }

    @IsTest
    static void groundsTheModelInTheOrgsActiveProgramCatalog() {
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];
        Id documentId = createFile('enrollment-form.pdf', '%PDF-1.4 sample');
        StubPromptService stub = new StubPromptService();
        stub.responseText = minimalGeneration();

        Test.startTest();
        serviceWith(stub).extractEnrollmentData(documentId);
        Test.stopTest();

        String catalog = (String) stub.capturedInputs.get('Input:programCatalog').value;
        System.assert(
            catalog.contains(program.Program_Code__c),
            'Active program codes must reach the prompt, or the model invents codes that ' +
            'EnrollmentService cannot resolve. Catalog was: ' + catalog
        );
    }

    @IsTest
    static void tellsTheModelWhenNoProgramsAreConfigured() {
        Id documentId = createFile('enrollment-form.pdf', '%PDF-1.4 sample');
        StubPromptService stub = new StubPromptService();
        stub.responseText = minimalGeneration();

        Test.startTest();
        serviceWith(stub).extractEnrollmentData(documentId);
        Test.stopTest();

        String catalog = (String) stub.capturedInputs.get('Input:programCatalog').value;
        System.assert(
            catalog.containsIgnoreCase('No active care programs'),
            'An empty catalog should say so explicitly rather than send an empty string.'
        );
    }

    @IsTest
    static void stampsProvenanceOnTheResult() {
        Id documentId = createFile('enrollment-form.pdf', '%PDF-1.4 sample');
        StubPromptService stub = new StubPromptService();
        stub.responseText = minimalGeneration();

        Test.startTest();
        EnrollmentExtractionResult result = serviceWith(stub).extractEnrollmentData(documentId);
        Test.stopTest();

        System.assertEquals('AI', result.extractionMode, 'A real extraction should not be labelled a mock.');
        System.assertEquals(String.valueOf(documentId), result.sourceDocumentId, 'Source file should be traceable.');
        System.assertEquals('enrollment-form.pdf', result.sourceFileName, 'File name should be recorded.');
        System.assertEquals(
            'Enrollment_Document_Extraction',
            result.promptTemplate,
            'The prompt template should be recorded for traceability.'
        );
        System.assertNotEquals(null, result.extractedAt, 'The extraction timestamp should be set.');
    }

    @IsTest
    static void rejectsAnUnsupportedFileTypeWithAnActionableMessage() {
        Id documentId = createFile('enrollment-form.docx', 'not really a word file');
        StubPromptService stub = new StubPromptService();

        Test.startTest();
        try {
            serviceWith(stub).extractEnrollmentData(documentId);
            System.assert(false, 'A Word document should be rejected.');
        } catch (AIExtractionService.AIExtractionException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('PDF'),
                'The message should tell the user to upload a PDF. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assertEquals(null, stub.capturedTemplateName, 'An invalid file should never reach the model.');
    }

    @IsTest
    static void rejectsANullDocumentId() {
        Test.startTest();
        try {
            serviceWith(new StubPromptService()).extractEnrollmentData(null);
            System.assert(false, 'A null document id should be rejected.');
        } catch (AIExtractionService.AIExtractionException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('no document'),
                'The message should name the missing document. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void surfacesATemplateFailureWithSetupGuidance() {
        Id documentId = createFile('enrollment-form.pdf', '%PDF-1.4 sample');
        StubPromptService stub = new StubPromptService();
        stub.failure = new PromptTemplateService.PromptTemplateException('Template not found');

        Test.startTest();
        try {
            serviceWith(stub).extractEnrollmentData(documentId);
            System.assert(false, 'A template failure should surface.');
        } catch (AIExtractionService.AIExtractionException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('activated'),
                'The message should point at template activation. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void doesNotFallBackToMockDataWhenTheModelFails() {
        Id documentId = createFile('enrollment-form.pdf', '%PDF-1.4 sample');
        StubPromptService stub = new StubPromptService();
        stub.failure = new PromptTemplateService.PromptTemplateException('Einstein is unavailable');

        Test.startTest();
        EnrollmentExtractionResult result;
        try {
            result = serviceWith(stub).extractEnrollmentData(documentId);
        } catch (AIExtractionService.AIExtractionException e) {
            result = null;
        }
        Test.stopTest();

        System.assertEquals(
            null,
            result,
            'Handing a specialist synthetic patient data to confirm would be worse than an error.'
        );
    }

    @IsTest
    static void surfacesAnUnparseableGeneration() {
        Id documentId = createFile('enrollment-form.pdf', '%PDF-1.4 sample');
        StubPromptService stub = new StubPromptService();
        stub.responseText = 'I was unable to read that document.';

        Test.startTest();
        try {
            serviceWith(stub).extractEnrollmentData(documentId);
            System.assert(false, 'A non-JSON generation should throw.');
        } catch (AIExtractionService.AIExtractionException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('JSON'),
                'The message should name the JSON problem. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    // ── Mock fixtures, retained for demos and other tests ──

    @IsTest
    static void mockExtractionIsCompleteAndConfident() {
        Test.startTest();
        EnrollmentExtractionResult result = AIExtractionMock.getMockExtraction();
        Test.stopTest();

        System.assert(result.isComplete, 'Mock extraction should be complete.');
        System.assertEquals('Sarah', result.firstName, 'Mock first name should be populated.');
        System.assertNotEquals(null, result.dateOfBirth, 'Mock DOB should be populated.');
        System.assert(result.patientConfidence >= 0.9, 'Mock patient confidence should be high.');
        System.assert(!result.warnings.isEmpty(), 'The mock demonstrates the warning path.');
    }

    @IsTest
    static void incompleteMockExtractionFlagsItsGaps() {
        Test.startTest();
        EnrollmentExtractionResult result = AIExtractionMock.getIncompleteExtraction();
        Test.stopTest();

        System.assert(!result.isComplete, 'Incomplete extraction should be flagged as incomplete.');
        System.assert(result.patientConfidence < 0.5, 'Confidence should be low.');
        System.assert(result.warnings.size() >= 3, 'Should have multiple warnings.');
    }

    @IsTest
    static void extractionResultDefaultsAreSafeForTheUi() {
        Test.startTest();
        EnrollmentExtractionResult result = new EnrollmentExtractionResult();
        Test.stopTest();

        System.assertEquals(false, result.isComplete, 'A new result is not complete.');
        System.assertEquals(0.0, result.patientConfidence, 'Confidence starts at zero.');
        System.assertNotEquals(null, result.warnings, 'Warnings must never be null for the LWC.');
        System.assertNotEquals(null, result.servicesRequested, 'Services must never be null for the LWC.');
    }
}

/**
 * @description Extracts enrollment data from an uploaded document.
 *
 *              Pipeline, per architecture/ai/README.md:
 *              File -> Prompt Builder (multimodal Flex template, Einstein Trust Layer)
 *                   -> JSON -> EnrollmentExtractionResult -> Review UI -> human confirmation
 *                   -> Salesforce records
 *
 *              The model reads the file itself: the ContentDocument id is passed as a File
 *              input on the template, so nothing here loads, encodes or transmits the document.
 *              That keeps the Apex heap out of the picture entirely and leaves masking,
 *              logging and model selection to the Trust Layer.
 *
 *              The program catalog is passed in as a second input. Without it the model returns
 *              a plausible program code read off the form, EnrollmentService cannot find it, and
 *              the specialist gets "Care Program not found" with no explanation. Grounding the
 *              code in this org's active programs turns a guess into a constrained choice.
 *
 *              This service does not fall back to mock data when the template is unavailable.
 *              Silently handing an enrollment specialist synthetic patient details to confirm
 *              would be worse than an error message. AIExtractionMock remains for tests and
 *              demos and is reached explicitly.
 */
public with sharing class AIExtractionService {
    @TestVisible
    private static final String TEMPLATE_API_NAME = 'Enrollment_Document_Extraction';

    @TestVisible
    private PromptTemplateService promptService = new PromptTemplateService();

    @TestVisible
    private CareProgramService programService = new CareProgramService();

    /**
     * @description Extract enrollment data from an uploaded document.
     * @param documentId ContentDocument or ContentVersion id of the uploaded file.
     * @return Structured extraction result with per-section confidence and warnings.
     * @throws AIExtractionException when the file cannot be used or the template fails.
     */
    public EnrollmentExtractionResult extractEnrollmentData(Id documentId) {
        EnrollmentDocument document;
        try {
            document = EnrollmentDocument.validate(documentId);
        } catch (EnrollmentDocument.EnrollmentDocumentException e) {
            // Already phrased for the specialist — pass it through unchanged.
            throw new AIExtractionException(e.getMessage());
        }

        String generatedText = generate(document);

        EnrollmentExtractionResult result;
        try {
            result = EnrollmentExtractionMapper.fromGeneratedText(generatedText);
        } catch (EnrollmentExtractionMapper.ExtractionMappingException e) {
            throw new AIExtractionException(e.getMessage());
        }

        stampProvenance(result, document);
        return result;
    }

    private String generate(EnrollmentDocument document) {
        Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:enrollmentDocument' => PromptTemplateService.recordValue(document.contentDocumentId),
            'Input:programCatalog' => PromptTemplateService.textValue(buildProgramCatalog()),
            'Input:receivedDate' => PromptTemplateService.textValue(String.valueOf(Date.today()))
        };

        try {
            return promptService.generate(TEMPLATE_API_NAME, inputParams);
        } catch (Exception e) {
            throw new AIExtractionException(
                'AI extraction could not run on "' + document.fileName + '". ' +
                'Check that the ' + TEMPLATE_API_NAME + ' prompt template is activated and that ' +
                'you have Einstein Generative AI access. Details: ' + e.getMessage()
            );
        }
    }

    /**
     * One line per active program, in a shape the model can match a form against and copy a
     * code from verbatim.
     */
    @TestVisible
    private String buildProgramCatalog() {
        List<Care_Program__c> programs = programService.getActivePrograms();
        if (programs.isEmpty()) {
            return 'No active care programs are configured in this org. Return null for programCode.';
        }

        List<String> lines = new List<String>();
        for (Care_Program__c program : programs) {
            lines.add(
                '- programCode: ' + program.Program_Code__c +
                ' | name: ' + program.Name +
                ' | therapy area: ' + blankToDash(program.Therapy_Area__c) +
                ' | product: ' + blankToDash(program.Product_Name__c)
            );
        }
        return String.join(lines, '\n');
    }

    private String blankToDash(String value) {
        return String.isBlank(value) ? '-' : value;
    }

    /** So a confirmed enrollment can be traced back to the file and prompt that produced it. */
    private void stampProvenance(EnrollmentExtractionResult result, EnrollmentDocument document) {
        result.extractionMode = 'AI';
        result.sourceDocumentId = String.valueOf(document.contentDocumentId);
        result.sourceFileName = document.fileName;
        result.promptTemplate = TEMPLATE_API_NAME;
        result.extractedAt = Datetime.now();
    }

    public class AIExtractionException extends Exception {}
}

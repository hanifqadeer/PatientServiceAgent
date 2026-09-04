/**
 * @description Interface for AI enrollment extraction.
 *              Accepts a document reference and returns structured enrollment data.
 *              Mock implementation returns synthetic data; architecture designed
 *              for future swap-in of real OCR/LLM service.
 *
 *              Per architecture AI rules:
 *              "File → OCR/document processing → AI structuring → Review UI
 *               → human confirmation → Salesforce records"
 */
public with sharing class AIExtractionService {

    /**
     * @description Extract enrollment data from a document.
     *              Currently delegates to AIExtractionMock.
     *              Swap to real implementation by changing this method body.
     * @param documentId ContentDocument or ContentVersion Id.
     * @return Structured extraction result with confidence scores.
     */
    public EnrollmentExtractionResult extractEnrollmentData(Id documentId) {
        // In production: call OCR service, parse response, build result
        // For MVP: delegate to mock implementation
        return AIExtractionMock.getMockExtraction();
    }
}

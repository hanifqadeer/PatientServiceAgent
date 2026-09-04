/**
 * @description Mock implementation of enrollment document extraction.
 *              Returns realistic synthetic data for demo and testing.
 *              Includes realistic confidence scores and one warning
 *              to demonstrate the review workflow handling edge cases.
 */
public with sharing class AIExtractionMock {

    /**
     * @description Returns a realistic mock extraction result.
     * @return EnrollmentExtractionResult populated with synthetic data.
     */
    public static EnrollmentExtractionResult getMockExtraction() {
        EnrollmentExtractionResult result = new EnrollmentExtractionResult();

        // Patient Identity
        result.firstName = 'Sarah';
        result.lastName = 'Johnson';
        result.dateOfBirth = Date.newInstance(1985, 3, 15);
        result.phone = '(555) 234-5678';
        result.email = 'sarah.johnson@example.com';
        result.street = '742 Evergreen Terrace';
        result.city = 'Springfield';
        result.state = 'IL';
        result.postalCode = '62704';
        result.preferredLanguage = 'English';
        result.communicationPreference = 'Phone';

        // HCP Information
        result.hcpFirstName = 'Michael';
        result.hcpLastName = 'Chen';
        result.hcpNpi = '1234567890';
        result.hcpSpecialty = 'Oncology';

        // HCO Information
        result.hcoName = 'Springfield Memorial Hospital';
        result.hcoSiteType = 'Hospital';

        // Program / Therapy
        result.programCode = 'ONCO-HUB-001';
        result.programName = 'Oncology Hub Services';
        result.therapyArea = 'Oncology';
        result.productName = 'Nexavar';

        // Payer Information
        result.payerName = 'Blue Cross Blue Shield';
        result.memberId = 'BCBS-9876543';
        result.groupNumber = 'GRP-12345';

        // Enrollment Metadata
        result.enrollmentSource = 'Fax';

        // Confidence Scores
        result.patientConfidence = 0.95;
        result.hcpConfidence = 0.88;
        result.programConfidence = 0.92;
        result.payerConfidence = 0.78;

        // Demonstrate an edge case: payer info is lower confidence
        result.warnings.add('Payer group number partially obscured — please verify.');
        result.isComplete = true;

        return result;
    }

    /**
     * @description Returns a mock extraction with incomplete/missing data.
     *              Used to test error handling flows.
     * @return EnrollmentExtractionResult with missing fields.
     */
    public static EnrollmentExtractionResult getIncompleteExtraction() {
        EnrollmentExtractionResult result = new EnrollmentExtractionResult();

        result.firstName = 'J';
        result.lastName = 'Martinez';
        result.dateOfBirth = null; // Missing
        result.phone = '(555) 000-0000';

        result.hcpLastName = 'Williams';
        result.hcpNpi = ''; // Missing

        result.programCode = ''; // Missing

        result.patientConfidence = 0.45;
        result.hcpConfidence = 0.30;
        result.programConfidence = 0.0;
        result.payerConfidence = 0.0;

        result.isComplete = false;
        result.warnings.add('Patient date of birth could not be extracted.');
        result.warnings.add('HCP NPI number is missing.');
        result.warnings.add('Program/therapy information not found on document.');
        result.warnings.add('No payer information detected.');

        return result;
    }
}

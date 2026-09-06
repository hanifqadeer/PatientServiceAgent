/**
 * @description Tests for EnrollmentExtractionMapper.
 *              Covers a clean generation, the messy shapes a model actually returns
 *              (code fences, prose, literal "null", out-of-range confidence), missing
 *              sections, and the review warnings the mapper adds on top of the model's.
 */
@IsTest
private class EnrollmentExtractionMapperTest {
    /** Mirrors the fields on the reference form in architecture/ai/prompts/. */
    private static String completeJson() {
        return '{' +
            '"documentType":"patient enrollment and consent form",' +
            '"externalReferenceNumber":"ENR-2026-00417",' +
            '"patient":{"firstName":"Sarah","lastName":"Johnson","dateOfBirth":"1985-03-15",' +
                '"phone":"(555) 234-5678","email":"sarah.johnson@example.com",' +
                '"street":"742 Evergreen Terrace","city":"Springfield","state":"IL",' +
                '"postalCode":"62704","country":"US","preferredLanguage":"English",' +
                '"communicationPreference":"Phone","confidence":0.95},' +
            '"hcp":{"firstName":"Michael","lastName":"Chen","npi":"1234567890",' +
                '"specialty":"Oncology","confidence":0.88},' +
            '"hco":{"name":"Springfield Memorial Hospital","siteType":"Hospital",' +
                '"taxId":"12-3456789","confidence":0.9},' +
            '"program":{"programCode":"ONCO-HUB-001","programName":"Oncology Hub Services",' +
                '"therapyArea":"Oncology","productName":"Nexavar","confidence":0.92},' +
            '"payer":{"payerName":"Blue Cross Blue Shield","memberId":"BCBS-9876543",' +
                '"groupNumber":"GRP-12345","confidence":0.78},' +
            '"enrollment":{"enrollmentSource":"Fax","enrollmentDate":"2026-09-04",' +
                '"servicesRequested":["Benefits Verification","Prior Authorization",' +
                    '"Copay Assistance","Nurse Educator"],' +
                '"patientConsentSigned":true,' +
                '"prescriberSignaturePresent":true,"confidence":0.9},' +
            '"warnings":["Payer group number partially obscured - please verify."]' +
        '}';
    }

    @IsTest
    static void mapsACompleteGeneration() {
        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText(completeJson());
        Test.stopTest();

        System.assertEquals('Sarah', result.firstName, 'Patient first name should map.');
        System.assertEquals('Johnson', result.lastName, 'Patient last name should map.');
        System.assertEquals(Date.newInstance(1985, 3, 15), result.dateOfBirth, 'DOB should parse from ISO.');
        System.assertEquals('1234567890', result.hcpNpi, 'HCP NPI should map.');
        System.assertEquals('12-3456789', result.hcoTaxId, 'HCO tax id should map.');
        System.assertEquals('ONCO-HUB-001', result.programCode, 'Program code should map.');
        System.assertEquals('BCBS-9876543', result.memberId, 'Member id should map.');
        System.assertEquals('Fax', result.enrollmentSource, 'Enrollment source should map.');
        System.assertEquals(true, result.patientConsentSigned, 'Consent flag should map.');
        System.assertEquals(0.95, result.patientConfidence, 'Patient confidence should map.');
        System.assert(result.isComplete, 'Last name and program code present means complete.');
    }

    @IsTest
    static void mapsTheFormsOwnReferenceNumberDateAndServices() {
        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText(completeJson());
        Test.stopTest();

        System.assertEquals(
            'ENR-2026-00417',
            result.externalReferenceNumber,
            'The intake number printed on the form should be captured for Case.External_Reference_Number__c.'
        );
        System.assertEquals(
            Date.newInstance(2026, 9, 4),
            result.enrollmentDate,
            'The date the form states it was received should be captured.'
        );
        System.assertEquals(4, result.servicesRequested.size(), 'Every ticked service should be captured.');
        System.assert(
            result.servicesRequested.contains('Prior Authorization'),
            'Ticked services should map verbatim.'
        );
    }

    @IsTest
    static void servicesRequestedDefaultsToAnEmptyListNotNull() {
        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText(
            '{"enrollment":{"enrollmentSource":"Web","confidence":0.5},"warnings":[]}'
        );
        Test.stopTest();

        System.assertNotEquals(null, result.servicesRequested, 'The list should never be null for the LWC.');
        System.assertEquals(0, result.servicesRequested.size(), 'No services ticked means an empty list.');
    }

    @IsTest
    static void overallConfidenceIsTheWeakestSectionNotTheAverage() {
        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText(completeJson());
        Test.stopTest();

        // patient 0.95, hcp 0.88, program 0.92, payer 0.78
        System.assertEquals(
            0.78,
            result.overallConfidence,
            'Overall confidence should be the weakest section so the reviewer knows where to look.'
        );
    }

    @IsTest
    static void toleratesMarkdownCodeFencesAndSurroundingProse() {
        String wrapped =
            'Here is the extracted data:\n\n```json\n' + completeJson() + '\n```\n\nLet me know if you need more.';

        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText(wrapped);
        Test.stopTest();

        System.assertEquals('Johnson', result.lastName, 'JSON should be recovered from a fenced response.');
    }

    @IsTest
    static void treatsLiteralNullStringsAndBlanksAsAbsent() {
        String json = '{"patient":{"firstName":"null","lastName":"Martinez","dateOfBirth":"",' +
            '"phone":"  ","confidence":0.4},"warnings":[]}';

        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText(json);
        Test.stopTest();

        System.assertEquals(null, result.firstName, 'The literal string "null" should map to null.');
        System.assertEquals(null, result.dateOfBirth, 'An empty date should map to null.');
        System.assertEquals(null, result.phone, 'A whitespace-only value should map to null.');
        System.assertEquals('Martinez', result.lastName, 'Real values should still map.');
    }

    @IsTest
    static void rejectsAnEnrollmentSourceTheOrgWouldNotAccept() {
        // Observed from a real extraction: a form reading "Secure portal" produced "Portal",
        // which belongs to communicationPreference. Enrollment_Source__c is a restricted
        // picklist, so this would have failed the Case insert after the patient was created.
        String json = '{"patient":{"lastName":"Marin","confidence":0.9},' +
            '"program":{"programCode":"TEST-RHEUM-101","confidence":0.9},' +
            '"enrollment":{"enrollmentSource":"Portal","confidence":0.7},"warnings":[]}';

        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText(json);
        Test.stopTest();

        System.assertEquals(
            null,
            result.enrollmentSource,
            'A value outside the picklist must not reach the Case insert.'
        );
        System.assert(
            containsText(result.warnings, 'enrollment source'),
            'The reviewer must be told which field to fix. Got: ' + result.warnings
        );
    }

    @IsTest
    static void normalisesControlledValuesToTheOrgsCasing() {
        String json = '{"patient":{"lastName":"Marin","preferredLanguage":"english",' +
            '"communicationPreference":"EMAIL","confidence":0.9},' +
            '"hcp":{"specialty":"rheumatology","confidence":0.8},' +
            '"hco":{"siteType":"clinic","confidence":0.8},' +
            '"enrollment":{"enrollmentSource":"fax","confidence":0.9},"warnings":[]}';

        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText(json);
        Test.stopTest();

        System.assertEquals('English', result.preferredLanguage, 'Casing should match the picklist.');
        System.assertEquals('Email', result.communicationPreference, 'Casing should match the picklist.');
        System.assertEquals('Rheumatology', result.hcpSpecialty, 'Casing should match the picklist.');
        System.assertEquals('Clinic', result.hcoSiteType, 'Casing should match the picklist.');
        System.assertEquals('Fax', result.enrollmentSource, 'Casing should match the picklist.');
    }

    @IsTest
    static void rejectsASiteTypeTheOrgWouldNotAccept() {
        // The reference form reads "Specialty clinic", which is not in Site_Type__c.
        String json = '{"patient":{"lastName":"Marin","confidence":0.9},' +
            '"hco":{"name":"Demo Harbor","siteType":"Specialty Practice","confidence":0.8},' +
            '"program":{"programCode":"X","confidence":0.9},"warnings":[]}';

        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText(json);
        Test.stopTest();

        System.assertEquals(null, result.hcoSiteType, 'An unmappable site type should be null.');
        System.assertEquals('Demo Harbor', result.hcoName, 'The rest of the section should survive.');
        System.assert(containsText(result.warnings, 'site type'), 'The field should be named in a warning.');
    }

    @IsTest
    static void clampsConfidenceIntoRange() {
        String json = '{"patient":{"lastName":"Doe","confidence":1.7},' +
            '"hcp":{"confidence":-3},"program":{"programCode":"X","confidence":"not a number"},' +
            '"warnings":[]}';

        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText(json);
        Test.stopTest();

        System.assertEquals(1.0, result.patientConfidence, 'Above 1 should clamp to 1.');
        System.assertEquals(0.0, result.hcpConfidence, 'Below 0 should clamp to 0.');
        System.assertEquals(0.0, result.programConfidence, 'An unparseable confidence should become 0.');
    }

    @IsTest
    static void survivesMissingSections() {
        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText('{"warnings":[]}');
        Test.stopTest();

        System.assertNotEquals(null, result, 'A near-empty object should still produce a result.');
        System.assertEquals(null, result.lastName, 'Absent sections leave fields null.');
        System.assertEquals(false, result.isComplete, 'Nothing extracted means not complete.');
        System.assert(result.warnings.size() >= 2, 'Missing name and program should both warn.');
    }

    @IsTest
    static void warnsWhenADateCannotBeReadButKeepsTheRest() {
        String json = '{"patient":{"lastName":"Doe","dateOfBirth":"March 15th, sometime","confidence":0.6},' +
            '"program":{"programCode":"ONCO-HUB-001","confidence":0.8},"warnings":[]}';

        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText(json);
        Test.stopTest();

        System.assertEquals(null, result.dateOfBirth, 'An unreadable date should be null, not an exception.');
        System.assertEquals('Doe', result.lastName, 'The rest of the extraction should survive.');
        System.assert(
            containsText(result.warnings, 'date of birth'),
            'The unreadable date should raise a warning naming the field.'
        );
    }

    @IsTest
    static void addsComplianceWarningsForMissingSignatures() {
        String json = '{"patient":{"lastName":"Doe","confidence":0.9},' +
            '"program":{"programCode":"ONCO-HUB-001","confidence":0.9},' +
            '"enrollment":{"patientConsentSigned":false,"prescriberSignaturePresent":false,"confidence":0.5},' +
            '"warnings":[]}';

        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText(json);
        Test.stopTest();

        System.assert(containsText(result.warnings, 'consent'), 'Unsigned consent must be flagged.');
        System.assert(
            containsText(result.warnings, 'prescriber signature'),
            'A missing prescriber signature must be flagged.'
        );
    }

    @IsTest
    static void carriesModelWarningsThrough() {
        String json = '{"patient":{"lastName":"Doe","confidence":0.9},' +
            '"program":{"programCode":"X","confidence":0.9},' +
            '"warnings":["HCP NPI was illegible.","Payer section was cut off."]}';

        Test.startTest();
        EnrollmentExtractionResult result = EnrollmentExtractionMapper.fromGeneratedText(json);
        Test.stopTest();

        System.assert(containsText(result.warnings, 'HCP NPI was illegible.'), 'Model warnings should survive.');
        System.assert(containsText(result.warnings, 'Payer section was cut off.'), 'All model warnings should survive.');
    }

    @IsTest
    static void throwsWhenThereIsNoJsonAtAll() {
        Test.startTest();
        try {
            EnrollmentExtractionMapper.fromGeneratedText('I could not read this document, sorry.');
            System.assert(false, 'A response with no JSON should throw.');
        } catch (EnrollmentExtractionMapper.ExtractionMappingException e) {
            System.assert(
                e.getMessage().contains('did not return JSON'),
                'The error should say the template returned no JSON. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void throwsOnMalformedJson() {
        Test.startTest();
        try {
            EnrollmentExtractionMapper.fromGeneratedText('{"patient":{"lastName":}}');
            System.assert(false, 'Malformed JSON should throw.');
        } catch (EnrollmentExtractionMapper.ExtractionMappingException e) {
            System.assert(
                e.getMessage().contains('malformed JSON'),
                'The error should name malformed JSON. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void throwsOnAnEmptyResponse() {
        Test.startTest();
        try {
            EnrollmentExtractionMapper.fromGeneratedText('   ');
            System.assert(false, 'An empty response should throw.');
        } catch (EnrollmentExtractionMapper.ExtractionMappingException e) {
            System.assert(
                e.getMessage().contains('empty response'),
                'The error should name the empty response. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    private static Boolean containsText(List<String> warnings, String fragment) {
        for (String warning : warnings) {
            if (warning.containsIgnoreCase(fragment)) {
                return true;
            }
        }
        return false;
    }
}

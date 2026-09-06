/**
 * @description Tests for the behaviour that keeps one record per person:
 *              patient matching, adding a second program to an existing patient,
 *              refusing a duplicate plan for the same program, syncing reviewer edits
 *              onto an existing patient, and linking the source form to what it created.
 */
@IsTest
private class EnrollmentMatchingTest {
    private static EnrollmentExtractionResult extractionFor(Account patient, String programCode) {
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(programCode);
        extraction.firstName = patient.FirstName;
        extraction.lastName = patient.LastName;
        extraction.dateOfBirth = patient.PersonBirthdate;
        extraction.email = patient.PersonEmail;
        return extraction;
    }

    private static Id createFile() {
        ContentVersion version = new ContentVersion(
            Title = 'Enrollment Form',
            PathOnClient = 'enrollment-form.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 sample'),
            IsMajorVersion = true
        );
        insert version;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
    }

    // ── Matching ──

    @IsTest
    static void matchesOnEmailAloneAndCallsItStrong() {
        Account patient = TestDataFactory.createPatients(1)[0];
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction('TP-1000');
        extraction.email = patient.PersonEmail;
        // Deliberately different name and DOB: email alone should still surface the patient.
        extraction.firstName = 'Totally';
        extraction.lastName = 'Different';
        extraction.dateOfBirth = Date.newInstance(1901, 1, 1);

        Test.startTest();
        List<PatientMatchResult> matches = new PatientService().findMatches(extraction);
        Test.stopTest();

        System.assertEquals(1, matches.size(), 'Email alone should surface the patient.');
        System.assertEquals(
            PatientMatchResult.STRENGTH_STRONG,
            matches[0].strength,
            'An email match identifies a person and should rank as strong.'
        );
    }

    @IsTest
    static void matchesOnLastNameAndDateOfBirthWhenEmailIsMissing() {
        Account patient = TestDataFactory.createPatients(1)[0];
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction('TP-1000');
        extraction.email = null; // Illegible on the fax.
        extraction.firstName = patient.FirstName;
        extraction.lastName = patient.LastName;
        extraction.dateOfBirth = patient.PersonBirthdate;

        Test.startTest();
        List<PatientMatchResult> matches = new PatientService().findMatches(extraction);
        Test.stopTest();

        System.assertEquals(1, matches.size(), 'Name and DOB should still find the patient.');
        System.assert(
            matches[0].matchReasons.contains('Same date of birth'),
            'The reason shown to the specialist should name what matched.'
        );
    }

    @IsTest
    static void returnsNothingForAGenuinelyNewPatient() {
        TestDataFactory.createPatients(1);
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction('TP-1000');
        extraction.firstName = 'Brand';
        extraction.lastName = 'NewPerson';
        extraction.email = 'brand.newperson@example.com';
        extraction.dateOfBirth = Date.newInstance(1974, 6, 2);

        Test.startTest();
        List<PatientMatchResult> matches = new PatientService().findMatches(extraction);
        Test.stopTest();

        System.assertEquals(0, matches.size(), 'An unrelated patient must not match.');
    }

    @IsTest
    static void doesNotMatchEveryPatientWhenTheFormHasNoEmail() {
        // A null email must not become "PersonEmail = null", which would match every
        // patient without an email address.
        List<Account> patients = TestDataFactory.createPatients(2);
        for (Account patient : patients) {
            patient.PersonEmail = null;
        }
        update patients;

        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction('TP-1000');
        extraction.email = null;
        extraction.firstName = 'Nobody';
        extraction.lastName = 'Here';
        extraction.dateOfBirth = null;

        Test.startTest();
        List<PatientMatchResult> matches = new PatientService().findMatches(extraction);
        Test.stopTest();

        System.assertEquals(0, matches.size(), 'A blank email must not match patients with no email.');
    }

    @IsTest
    static void reportsExistingPlansAndFlagsTheRequestedProgram() {
        Account patient = TestDataFactory.createPatients(1)[0];
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];
        new PatientSupportPlanService().createPlan(patient.Id, program.Id, 'Fax', null);

        Test.startTest();
        List<PatientMatchResult> matches = new PatientService()
            .findMatches(extractionFor(patient, program.Program_Code__c));
        Test.stopTest();

        System.assertEquals(1, matches.size(), 'The patient should match.');
        System.assertEquals(1, matches[0].existingPlans.size(), 'Existing plans should be reported.');
        System.assert(
            matches[0].hasPlanForRequestedProgram,
            'An open plan for the same program is the duplicate this screen exists to prevent.'
        );
    }

    // ── Enrolling an existing patient ──

    @IsTest
    static void addsASecondProgramToAnExistingPatientWithoutCreatingAnother() {
        Account patient = TestDataFactory.createPatients(1)[0];
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(2);
        new PatientSupportPlanService().createPlan(patient.Id, programs[0].Id, 'Fax', null);

        Integer patientsBefore = [SELECT COUNT() FROM Account WHERE RecordType.DeveloperName = 'Patient'];

        Test.startTest();
        EnrollmentService.EnrollmentResult result = new EnrollmentService().processEnrollment(
            extractionFor(patient, programs[1].Program_Code__c), patient.Id
        );
        Test.stopTest();

        System.assertEquals(patient.Id, result.patientId, 'The existing patient should be reused.');
        System.assert(!result.isNewPatient, 'No new patient record should be created.');
        System.assertEquals(
            patientsBefore,
            [SELECT COUNT() FROM Account WHERE RecordType.DeveloperName = 'Patient'],
            'Patient count must not grow. HCP and HCO accounts are created separately and by design.'
        );
        System.assertEquals(
            2,
            [SELECT COUNT() FROM Case WHERE AccountId = :patient.Id AND RecordType.DeveloperName = 'Patient_Support_Plan'],
            'The second program should produce a second support plan.'
        );
    }

    @IsTest
    static void refusesASecondOpenPlanForTheSameProgram() {
        Account patient = TestDataFactory.createPatients(1)[0];
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];
        Case existing = new PatientSupportPlanService().createPlan(patient.Id, program.Id, 'Fax', null);

        Test.startTest();
        try {
            new EnrollmentService().processEnrollment(
                extractionFor(patient, program.Program_Code__c), patient.Id
            );
            System.assert(false, 'A duplicate plan for the same program should be refused.');
        } catch (EnrollmentService.EnrollmentException e) {
            System.assert(
                e.getMessage().contains('already has an open support plan'),
                'The message should explain the clash. Got: ' + e.getMessage()
            );
            System.assert(
                e.getMessage().contains([SELECT CaseNumber FROM Case WHERE Id = :existing.Id].CaseNumber),
                'The message should name the plan to work instead.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void syncsReviewerEditsOntoTheExistingPatient() {
        Account patient = TestDataFactory.createPatients(1)[0];
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];

        EnrollmentExtractionResult extraction = extractionFor(patient, program.Program_Code__c);
        extraction.phone = '(555) 999-0000';          // Corrected on the review screen.
        extraction.preferredLanguage = 'Spanish';
        extraction.email = patient.PersonEmail;        // Unchanged.

        Test.startTest();
        EnrollmentService.EnrollmentResult result = new EnrollmentService()
            .processEnrollment(extraction, patient.Id);
        Test.stopTest();

        Account reloaded = [
            SELECT Phone, Preferred_Language__c, PersonEmail FROM Account WHERE Id = :patient.Id
        ];
        System.assertEquals('(555) 999-0000', reloaded.Phone, 'A corrected phone must reach the record.');
        System.assertEquals('Spanish', reloaded.Preferred_Language__c, 'A corrected language must reach the record.');
        System.assert(
            result.updatedPatientFields.contains('Phone'),
            'The result should report what changed. Got: ' + result.updatedPatientFields
        );
        System.assert(
            !result.updatedPatientFields.contains('Email'),
            'Unchanged values must not be reported as edits.'
        );
    }

    @IsTest
    static void neverBlanksExistingDataWithAFieldTheFormLacks() {
        Account patient = TestDataFactory.createPatients(1)[0];
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];

        EnrollmentExtractionResult extraction = extractionFor(patient, program.Program_Code__c);
        extraction.phone = null; // Illegible on this form.

        Test.startTest();
        new EnrollmentService().processEnrollment(extraction, patient.Id);
        Test.stopTest();

        System.assertNotEquals(
            null,
            [SELECT Phone FROM Account WHERE Id = :patient.Id].Phone,
            'A missing value on the form must not erase data already held.'
        );
    }

    // ── Document linking ──

    @IsTest
    static void linksTheSourceFormToBothThePlanAndThePatient() {
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(program.Program_Code__c);
        Id documentId = createFile();

        Test.startTest();
        EnrollmentService.EnrollmentResult result = new EnrollmentService()
            .processEnrollment(extraction, null, documentId);
        Test.stopTest();

        System.assert(result.documentLinked, 'The result should report the document was linked.');

        Set<Id> linkedTo = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId FROM ContentDocumentLink WHERE ContentDocumentId = :documentId
        ]) {
            linkedTo.add(link.LinkedEntityId);
        }
        System.assert(linkedTo.contains(result.planId), 'The form should be visible from the support plan.');
        System.assert(linkedTo.contains(result.patientId), 'The form should be visible from the patient.');
    }

    @IsTest
    static void enrollsWithoutADocumentWhenNoneIsSupplied() {
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(program.Program_Code__c);

        Test.startTest();
        EnrollmentService.EnrollmentResult result = new EnrollmentService()
            .processEnrollment(extraction, null, null);
        Test.stopTest();

        System.assertNotEquals(null, result.planId, 'Enrollment should still work with no file.');
        System.assert(!result.documentLinked, 'Nothing to link means documentLinked stays false.');
    }

    // ── Result payload used by the success screen ──

    @IsTest
    static void returnsTheDetailTheSuccessScreenShows() {
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(program.Program_Code__c);

        Test.startTest();
        EnrollmentService.EnrollmentResult result = new EnrollmentService()
            .processEnrollment(extraction, null, null);
        Test.stopTest();

        System.assertNotEquals(null, result.patientName, 'The success screen needs the patient name.');
        System.assertNotEquals(null, result.planNumber, 'The success screen needs the plan number.');
        System.assertEquals(program.Name, result.programName, 'The success screen needs the program name.');
    }

    @IsTest
    static void validatesTheProgramBeforeCreatingAnyPatient() {
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction('NO-SUCH-PROGRAM');
        Integer patientsBefore = [SELECT COUNT() FROM Account WHERE RecordType.DeveloperName = 'Patient'];

        Test.startTest();
        try {
            new EnrollmentService().processEnrollment(extraction, null, null);
            System.assert(false, 'An unknown program should be refused.');
        } catch (EnrollmentService.EnrollmentException e) {
            System.assert(e.getMessage().contains('NO-SUCH-PROGRAM'), 'The message should name the code.');
        }
        Test.stopTest();

        System.assertEquals(
            patientsBefore,
            [SELECT COUNT() FROM Account WHERE RecordType.DeveloperName = 'Patient'],
            'A bad program code must not leave an orphan patient behind.'
        );
    }

    // ── Care Program lookup ──

    @IsTest
    static void prefersTheSelectedProgramRecordOverTheCodeOnTheForm() {
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(2);
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(
            programs[0].Program_Code__c
        );
        // The specialist corrected the program on the review screen; the code is now stale.
        extraction.careProgramId = programs[1].Id;

        Test.startTest();
        EnrollmentService.EnrollmentResult result = new EnrollmentService()
            .processEnrollment(extraction, null, null);
        Test.stopTest();

        System.assertEquals(
            programs[1].Id,
            result.programId,
            'A record the specialist chose must win over a code read off the document.'
        );
        System.assertEquals(
            programs[1].Id,
            [SELECT Care_Program__c FROM Case WHERE Id = :result.planId].Care_Program__c,
            'The support plan must link to the selected program.'
        );
    }

    @IsTest
    static void fallsBackToTheProgramCodeWhenNoRecordWasSelected() {
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(
            program.Program_Code__c
        );
        extraction.careProgramId = null; // Payload built before the lookup existed.

        Test.startTest();
        EnrollmentService.EnrollmentResult result = new EnrollmentService()
            .processEnrollment(extraction, null, null);
        Test.stopTest();

        System.assertEquals(program.Id, result.programId, 'The code should still resolve.');
    }

    @IsTest
    static void survivesAMalformedProgramIdFromTheBrowser() {
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(
            program.Program_Code__c
        );
        extraction.careProgramId = 'not-an-id';

        Test.startTest();
        EnrollmentService.EnrollmentResult result = new EnrollmentService()
            .processEnrollment(extraction, null, null);
        Test.stopTest();

        System.assertEquals(
            program.Id,
            result.programId,
            'A malformed id should fall back to the code, not throw an opaque error.'
        );
    }

    @IsTest
    static void resolvesTheExtractedCodeToACareProgramRecord() {
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];
        EnrollmentExtractionResult extraction = new EnrollmentExtractionResult();
        extraction.programCode = program.Program_Code__c.toLowerCase(); // Casing differs on the fax.

        Test.startTest();
        new AIExtractionService().resolveCareProgram(
            extraction, new List<Care_Program__c>{ program }
        );
        Test.stopTest();

        System.assertEquals(program.Id, extraction.careProgramId, 'The code should resolve to a record.');
        System.assertEquals(
            program.Program_Code__c,
            extraction.programCode,
            'Casing should normalise to the record so the UI shows the canonical code.'
        );
        System.assertEquals(
            program.Therapy_Area__c,
            extraction.therapyArea,
            'Program details should come from the record, not the document.'
        );
    }

    @IsTest
    static void warnsWhenTheExtractedCodeMatchesNoActiveProgram() {
        EnrollmentExtractionResult extraction = new EnrollmentExtractionResult();
        extraction.programCode = 'TEST-RHEUM-101';

        Test.startTest();
        new AIExtractionService().resolveCareProgram(extraction, new List<Care_Program__c>());
        Test.stopTest();

        System.assertEquals(null, extraction.careProgramId, 'Nothing should be resolved.');
        Boolean warned = false;
        for (String warning : extraction.warnings) {
            warned = warned || warning.contains('TEST-RHEUM-101');
        }
        System.assert(warned, 'The specialist needs to know the code matched nothing. Got: ' + extraction.warnings);
    }

    @IsTest
    static void explainsWhenTheFormNamedNoProgramAtAll() {
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(null);
        extraction.programCode = null;

        Test.startTest();
        try {
            new EnrollmentService().processEnrollment(extraction, null, null);
            System.assert(false, 'A missing program should be refused.');
        } catch (EnrollmentService.EnrollmentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('select a program'),
                'A blank code needs different guidance than a wrong one. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }
}

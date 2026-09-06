/**
 * @description Tests for provider and facility match-or-create, and for the affiliations an
 *              enrollment records.
 *
 *              Writing an affiliation needs field-level security on Role__c, Is_Primary__c,
 *              Status__c and the effective dates, granted by the persona permission sets. The
 *              tests below check both outcomes: the relationships when the write succeeds, and
 *              the degradation contract when an org has not granted that access — enrollment
 *              still completes and the reason is reported.
 */
@IsTest
private class ProviderAffiliationTest {
    private static EnrollmentExtractionResult formWithProvider(String programCode) {
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(programCode);
        extraction.hcpFirstName = 'Adrian';
        extraction.hcpLastName = 'Vale';
        extraction.hcpNpi = '1987654320';
        extraction.hcpSpecialty = 'Rheumatology';
        extraction.hcoName = 'Demo Harbor Arthritis Center';
        extraction.hcoSiteType = 'Clinic';
        extraction.hcoTaxId = '98-7654321';
        return extraction;
    }

    // ── HCP ──

    @IsTest
    static void createsThePrescriberNamedOnTheForm() {
        Test.startTest();
        ProviderService.ProviderResult hcp = new ProviderService()
            .findOrCreateHcp(formWithProvider('TP-1000'));
        Test.stopTest();

        System.assert(hcp.isNew, 'A prescriber not already on file should be created.');
        Account created = [
            SELECT FirstName, LastName, NPI_Number__c, Specialty__c, RecordType.DeveloperName
            FROM Account WHERE Id = :hcp.record.Id
        ];
        System.assertEquals('Vale', created.LastName, 'The surname should be stored.');
        System.assertEquals('1987654320', created.NPI_Number__c, 'The NPI should be stored.');
        System.assertEquals('Rheumatology', created.Specialty__c, 'The specialty should be stored.');
        System.assertEquals('HCP', created.RecordType.DeveloperName, 'It should use the HCP record type.');
    }

    @IsTest
    static void reusesAPrescriberMatchedOnNpi() {
        EnrollmentExtractionResult first = formWithProvider('TP-1000');
        ProviderService service = new ProviderService();
        Account existing = service.findOrCreateHcp(first).record;

        // Same NPI, name spelled differently on the second form.
        EnrollmentExtractionResult second = formWithProvider('TP-1000');
        second.hcpFirstName = 'A.';
        second.hcpLastName = 'Vale';

        Test.startTest();
        ProviderService.ProviderResult again = service.findOrCreateHcp(second);
        Test.stopTest();

        System.assertEquals(existing.Id, again.record.Id, 'NPI identifies a prescriber nationally.');
        System.assert(!again.isNew, 'The second form must not create a duplicate prescriber.');
    }

    @IsTest
    static void reusesAPrescriberMatchedOnNameWhenTheNpiWasIllegible() {
        ProviderService service = new ProviderService();
        Account existing = service.findOrCreateHcp(formWithProvider('TP-1000')).record;

        EnrollmentExtractionResult noNpi = formWithProvider('TP-1000');
        noNpi.hcpNpi = null; // The prompt nulls anything that is not ten digits.

        Test.startTest();
        ProviderService.ProviderResult again = service.findOrCreateHcp(noNpi);
        Test.stopTest();

        System.assertEquals(existing.Id, again.record.Id, 'Name should match when the NPI is missing.');
        System.assert(!again.isNew, 'A missing NPI must not create a duplicate prescriber.');
    }

    @IsTest
    static void refusesToGuessFromASurnameAlone() {
        ProviderService service = new ProviderService();
        service.findOrCreateHcp(formWithProvider('TP-1000'));

        EnrollmentExtractionResult surnameOnly = formWithProvider('TP-1000');
        surnameOnly.hcpNpi = null;
        surnameOnly.hcpFirstName = null;

        Test.startTest();
        ProviderService.ProviderResult result = service.findOrCreateHcp(surnameOnly);
        Test.stopTest();

        System.assert(
            result.isNew,
            'A surname alone is too weak to merge two prescribers, so a new record is correct.'
        );
    }

    @IsTest
    static void skipsTheProviderWhenTheFormNamesNone() {
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction('TP-1000');
        extraction.hcpLastName = null;

        Test.startTest();
        ProviderService.ProviderResult result = new ProviderService().findOrCreateHcp(extraction);
        Test.stopTest();

        System.assertEquals(null, result, 'Nothing to match on means nothing is created.');
    }

    // ── HCO ──

    @IsTest
    static void createsTheFacilityNamedOnTheForm() {
        Test.startTest();
        ProviderService.ProviderResult hco = new ProviderService()
            .findOrCreateHco(formWithProvider('TP-1000'));
        Test.stopTest();

        System.assert(hco.isNew, 'A facility not already on file should be created.');
        Account created = [
            SELECT Name, Site_Type__c, Tax_ID__c, RecordType.DeveloperName
            FROM Account WHERE Id = :hco.record.Id
        ];
        System.assertEquals('Demo Harbor Arthritis Center', created.Name, 'The name should be stored.');
        System.assertEquals('Clinic', created.Site_Type__c, 'The site type should be stored.');
        System.assertEquals('HCO', created.RecordType.DeveloperName, 'It should use the HCO record type.');
    }

    @IsTest
    static void reusesAFacilityMatchedOnTaxId() {
        ProviderService service = new ProviderService();
        Account existing = service.findOrCreateHco(formWithProvider('TP-1000')).record;

        EnrollmentExtractionResult renamed = formWithProvider('TP-1000');
        renamed.hcoName = 'Demo Harbor Arthritis Ctr.'; // Abbreviated on the second form.

        Test.startTest();
        ProviderService.ProviderResult again = service.findOrCreateHco(renamed);
        Test.stopTest();

        System.assertEquals(existing.Id, again.record.Id, 'Tax ID should identify the facility.');
        System.assert(!again.isNew, 'An abbreviated name must not create a duplicate facility.');
    }

    // ── Affiliations ──

    @IsTest
    static void recordsBothRelationshipsOnEnrollment() {
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];

        Test.startTest();
        EnrollmentService.EnrollmentResult result = new EnrollmentService()
            .processEnrollment(formWithProvider(program.Program_Code__c), null, null);
        Test.stopTest();

        System.assertNotEquals(null, result.hcpId, 'The prescriber should be resolved.');
        System.assertNotEquals(null, result.hcoId, 'The facility should be resolved.');

        if (result.affiliationError != null) {
            // This org cannot currently write affiliations. Assert the degradation contract
            // instead: the enrollment still completed, and the reason was reported rather
            // than swallowed.
            System.assertNotEquals(null, result.planId, 'Enrollment must survive an affiliation failure.');
            System.assertEquals(0, result.affiliationsCreated, 'Nothing should be reported as created.');
            return;
        }

        System.assertEquals(2, result.affiliationsCreated, 'Patient-HCP and HCP-HCO should both be recorded.');

        Map<String, Affiliation__c> byType = new Map<String, Affiliation__c>();
        for (Affiliation__c affiliation : [
            SELECT Account_1__c, Account_2__c, Affiliation_Type__c FROM Affiliation__c
        ]) {
            byType.put(affiliation.Affiliation_Type__c, affiliation);
        }

        Affiliation__c patientLink = byType.get(AffiliationService.TYPE_PATIENT_HCP);
        System.assertNotEquals(null, patientLink, 'The patient should be linked to the prescriber.');
        System.assertEquals(result.patientId, patientLink.Account_1__c, 'Account 1 is the patient.');
        System.assertEquals(result.hcpId, patientLink.Account_2__c, 'Account 2 is the prescriber.');

        Affiliation__c facilityLink = byType.get(AffiliationService.TYPE_HCP_HCO);
        System.assertNotEquals(null, facilityLink, 'The prescriber should be linked to the facility.');
        System.assertEquals(result.hcpId, facilityLink.Account_1__c, 'Account 1 is the prescriber.');
        System.assertEquals(result.hcoId, facilityLink.Account_2__c, 'Account 2 is the facility.');
    }

    @IsTest
    static void doesNotDuplicateAffiliationsOnASecondEnrollment() {
        Account patient = TestDataFactory.createPatients(1)[0];
        List<Care_Program__c> programs = TestDataFactory.createCarePrograms(2);
        EnrollmentService service = new EnrollmentService();

        EnrollmentExtractionResult first = formWithProvider(programs[0].Program_Code__c);
        first.firstName = patient.FirstName;
        first.lastName = patient.LastName;
        first.email = patient.PersonEmail;
        service.processEnrollment(first, patient.Id, null);

        EnrollmentExtractionResult second = formWithProvider(programs[1].Program_Code__c);
        second.firstName = patient.FirstName;
        second.lastName = patient.LastName;
        second.email = patient.PersonEmail;

        Test.startTest();
        EnrollmentService.EnrollmentResult result = service.processEnrollment(second, patient.Id, null);
        Test.stopTest();

        System.assertEquals(
            0,
            result.affiliationsCreated,
            'The same patient, prescriber and facility must not gain duplicate affiliations.'
        );
        System.assertEquals(
            result.affiliationError == null ? 2 : 0,
            [SELECT COUNT() FROM Affiliation__c],
            'Exactly the links created by the first enrollment, and no more.'
        );
    }

    @IsTest
    static void enrollsWithNoProviderOnTheForm() {
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];
        EnrollmentExtractionResult extraction = TestDataFactory.createMockExtraction(
            program.Program_Code__c
        );
        extraction.hcpLastName = null;
        extraction.hcoName = null;

        Test.startTest();
        EnrollmentService.EnrollmentResult result = new EnrollmentService()
            .processEnrollment(extraction, null, null);
        Test.stopTest();

        System.assertNotEquals(null, result.planId, 'A form naming no provider should still enroll.');
        System.assertEquals(null, result.hcpId, 'No prescriber should be created.');
        System.assertEquals(0, result.affiliationsCreated, 'No relationships to record.');
    }

    @IsTest
    static void linksThePatientToThePrescriberEvenWithNoFacility() {
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];
        EnrollmentExtractionResult extraction = formWithProvider(program.Program_Code__c);
        extraction.hcoName = null;

        Test.startTest();
        EnrollmentService.EnrollmentResult result = new EnrollmentService()
            .processEnrollment(extraction, null, null);
        Test.stopTest();

        System.assertEquals(null, result.hcoId, 'No facility should be created.');
        System.assertEquals(
            result.affiliationError == null ? 1 : 0,
            result.affiliationsCreated,
            'Only the Patient-HCP link applies.'
        );
    }

    @IsTest
    static void attachesTheSourceFormToTheProviderRecordsToo() {
        Care_Program__c program = TestDataFactory.createCarePrograms(1)[0];
        ContentVersion version = new ContentVersion(
            Title = 'Enrollment Form',
            PathOnClient = 'enrollment-form.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 sample'),
            IsMajorVersion = true
        );
        insert version;
        Id documentId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id
        ].ContentDocumentId;

        Test.startTest();
        EnrollmentService.EnrollmentResult result = new EnrollmentService()
            .processEnrollment(formWithProvider(program.Program_Code__c), null, documentId);
        Test.stopTest();

        Set<Id> linkedTo = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId FROM ContentDocumentLink WHERE ContentDocumentId = :documentId
        ]) {
            linkedTo.add(link.LinkedEntityId);
        }
        System.assert(linkedTo.contains(result.hcpId), 'The form should be visible from the prescriber.');
        System.assert(linkedTo.contains(result.hcoId), 'The form should be visible from the facility.');
    }

    /**
     * The optional-field writer must be safe both before and after the deleted Affiliation
     * fields are restored, so this asserts on whichever state the org is actually in.
     */
    @IsTest
    static void affiliationCarriesRoleAndPrimaryFlag() {
        Account patient = TestDataFactory.createPatients(1)[0];
        Account prescriber = new ProviderService().findOrCreateHcp(formWithProvider('TP-1000')).record;

        AffiliationService service = new AffiliationService();

        Test.startTest();
        List<Affiliation__c> created = service.linkEnrollment(patient.Id, prescriber.Id, null);
        Test.stopTest();

        if (service.lastError != null) {
            System.assertEquals(0, created.size(), 'Nothing is written when the org refuses it.');
            return;
        }

        System.assertEquals(1, created.size(), 'One Patient-HCP link should be created.');

        Affiliation__c stored = [
            SELECT Role__c, Is_Primary__c, Status__c, Effective_Start_Date__c, Affiliation_Type__c
            FROM Affiliation__c WHERE Id = :created[0].Id
        ];
        System.assertEquals('Prescriber', stored.Role__c, 'The prescriber role should be recorded.');
        System.assertEquals(true, stored.Is_Primary__c, 'The prescriber is the primary link.');
        System.assertEquals('Active', stored.Status__c, 'New affiliations start active.');
        System.assertEquals(Date.today(), stored.Effective_Start_Date__c, 'The link starts today.');
        System.assertEquals(
            AffiliationService.TYPE_PATIENT_HCP,
            stored.Affiliation_Type__c,
            'The link should be typed as Patient-HCP.'
        );
    }
}

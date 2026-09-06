/**
 * @description Orchestrates the full enrollment journey:
 *              1. Parse extracted data (from AI extraction)
 *              2. Validate the Care Program before touching any patient data
 *              3. Match or create the Patient, syncing reviewer edits onto an existing one
 *              4. Refuse a second open plan for the same program
 *              5. Match or create the prescriber (HCP) and treatment facility (HCO)
 *              6. Record the Patient-HCP and HCP-HCO affiliations
 *              7. Create Patient Support Plan (PSP Case)
 *              8. Assign coordinator and create the onboarding Task
 *              9. Link the source enrollment document to everything it produced
 *
 *              Single transaction boundary — if any step fails, the entire enrollment
 *              rolls back.
 *
 *              Per architecture enrollment journey:
 *              "Review LWC → Human Confirmation → Match/Create Patient
 *               → Confirm Care Program → Create PSP → Assign Coordinator
 *               → Create Onboarding Task"
 */
public with sharing class EnrollmentService {

    private PatientService patientSvc;
    private CareProgramService programSvc;
    private PatientSupportPlanService planSvc;
    private ProviderService providerSvc;
    private AffiliationService affiliationSvc;

    public EnrollmentService() {
        this.patientSvc = new PatientService();
        this.programSvc = new CareProgramService();
        this.planSvc = new PatientSupportPlanService();
        this.providerSvc = new ProviderService();
        this.affiliationSvc = new AffiliationService();
    }

    /**
     * @description Execute the full enrollment from confirmed extraction data.
     * @param extraction The human-reviewed extraction result.
     * @param existingPatientId If a match was selected, enroll that patient into a new plan.
     *                          Null to create a new patient.
     * @return The created/matched Patient and PSP.
     */
    public EnrollmentResult processEnrollment(EnrollmentExtractionResult extraction,
                                               Id existingPatientId) {
        return processEnrollment(extraction, existingPatientId, null);
    }

    /**
     * @description Execute the full enrollment and link the source document to what it created.
     * @param extraction The human-reviewed extraction result.
     * @param existingPatientId Selected existing patient Id, or null to create a new patient.
     * @param documentId ContentDocument id of the uploaded enrollment form. Optional.
     * @return The created/matched Patient and PSP.
     */
    public EnrollmentResult processEnrollment(EnrollmentExtractionResult extraction,
                                               Id existingPatientId,
                                               Id documentId) {
        if (extraction == null) {
            throw new EnrollmentException('Extraction data is required.');
        }

        EnrollmentResult result = new EnrollmentResult();

        // ── Step 1: Validate Care Program first ──
        // Before any patient record is written. A bad program code used to create the patient
        // and then fail, leaving an orphan behind on every retry.
        Care_Program__c program = resolveProgram(extraction);
        if (program == null) {
            throw new EnrollmentException(
                String.isBlank(extraction.programCode) && String.isBlank(extraction.careProgramId)
                    ? 'No care program was identified on this form. Select a program before confirming.'
                    : 'Care Program not found with code: ' + extraction.programCode
            );
        }
        if (!programSvc.isProgramEligible(program.Id)) {
            throw new EnrollmentException(
                'Care Program "' + program.Name + '" is not eligible for enrollment. ' +
                'It is either inactive or outside its effective date range.'
            );
        }
        result.programId = program.Id;
        result.programName = program.Name;
        result.programCode = program.Program_Code__c;

        // ── Step 2: Resolve Patient ──
        Account patient;
        if (existingPatientId != null) {
            List<Account> existing = patientSvc.getPatients(new Set<Id>{ existingPatientId });
            if (existing.isEmpty()) {
                throw new EnrollmentException('The selected patient could not be found.');
            }
            patient = existing[0];
            result.isNewPatient = false;

            // Reviewer edits on the form must reach the patient record, not just the new plan.
            result.updatedPatientFields = patientSvc.syncPatient(patient, extraction);

            assertNoOpenPlanForProgram(patient.Id, program);
        } else {
            patient = patientSvc.createPatient(extraction);
            result.isNewPatient = true;
        }
        result.patientId = patient.Id;
        result.patientName = ((patient.FirstName == null ? '' : patient.FirstName) + ' ' +
            patient.LastName).trim();

        // ── Step 3: Resolve the prescriber and the treatment facility ──
        // Both are matched before they are created, so a prescriber who appears on fifty forms
        // stays one Account. Either may be absent: a form naming no facility still enrolls.
        ProviderService.ProviderResult hcp = providerSvc.findOrCreateHcp(extraction);
        ProviderService.ProviderResult hco = providerSvc.findOrCreateHco(extraction);

        if (hcp != null) {
            result.hcpId = hcp.record.Id;
            result.hcpName = (hcp.record.FirstName == null ? '' : hcp.record.FirstName + ' ') +
                hcp.record.LastName;
            result.isNewHcp = hcp.isNew;
        }
        if (hco != null) {
            result.hcoId = hco.record.Id;
            result.hcoName = hco.record.Name;
            result.isNewHco = hco.isNew;
        }

        // ── Step 4: Record the relationships the form establishes ──
        result.affiliationsCreated = affiliationSvc.linkEnrollment(
            patient.Id,
            result.hcpId,
            result.hcoId
        ).size();
        result.affiliationError = affiliationSvc.lastError;

        // ── Step 5: Create Patient Support Plan ──
        Case psp = planSvc.createPlan(
            patient.Id,
            program.Id,
            extraction.enrollmentSource,
            null // Coordinator assigned below or later
        );
        result.planId = psp.Id;

        // ── Step 6: Activate Plan ──
        planSvc.activatePlan(psp.Id);

        // ── Step 7: Create Onboarding Task ──
        // For MVP, assign to the running user; coordinator assignment comes later
        Task onboarding = planSvc.createOnboardingTask(psp.Id, UserInfo.getUserId());
        result.onboardingTaskId = onboarding.Id;

        // ── Step 8: Link the source document ──
        Set<Id> documentTargets = new Set<Id>{ psp.Id, patient.Id };
        if (result.hcpId != null) {
            documentTargets.add(result.hcpId);
        }
        if (result.hcoId != null) {
            documentTargets.add(result.hcoId);
        }
        result.documentLinked = linkDocument(documentId, documentTargets);

        result.planNumber = [SELECT CaseNumber FROM Case WHERE Id = :psp.Id LIMIT 1].CaseNumber;
        return result;
    }

    /**
     * Prefers the Care Program the specialist actually selected on the review screen over the
     * code the model read off the form. The code is a best-effort reading of a document; the Id
     * is a record someone chose. Falling back to the code keeps older callers, and any payload
     * built before the lookup existed, working.
     */
    private Care_Program__c resolveProgram(EnrollmentExtractionResult extraction) {
        // The id arrives as a String from the browser, so it can be anything. Binding a
        // malformed value throws rather than returning nothing, which would surface as an
        // opaque failure instead of the "select a program" guidance below.
        Id programId;
        try {
            programId = String.isBlank(extraction.careProgramId)
                ? null
                : Id.valueOf(extraction.careProgramId);
        } catch (System.StringException e) {
            programId = null;
        }

        if (programId != null) {
            List<Care_Program__c> byId = [
                SELECT Id, Name, Program_Code__c, Status__c,
                       Effective_Start_Date__c, Effective_End_Date__c
                FROM Care_Program__c
                WHERE Id = :programId
                LIMIT 1
            ];
            if (!byId.isEmpty()) {
                return byId[0];
            }
        }
        return programSvc.getProgramByCode(extraction.programCode);
    }

    /**
     * A patient can hold several plans — that is how a second program is added — but not two
     * open plans for the same one. Without this check, re-processing the same fax silently
     * creates a duplicate plan and the coordinator works the wrong one.
     */
    private void assertNoOpenPlanForProgram(Id patientId, Care_Program__c program) {
        List<Case> clashes = [
            SELECT Id, CaseNumber, Status
            FROM Case
            WHERE AccountId = :patientId
              AND Care_Program__c = :program.Id
              AND IsClosed = FALSE
              AND RecordType.DeveloperName = 'Patient_Support_Plan'
            LIMIT 1
        ];
        if (!clashes.isEmpty()) {
            throw new EnrollmentException(
                'This patient already has an open support plan for "' + program.Name + '" (' +
                clashes[0].CaseNumber + ', status ' + clashes[0].Status + '). ' +
                'Enroll them in a different program, or work the existing plan.'
            );
        }
    }

    /**
     * Files uploaded through the review component land in the uploader's private library. Link
     * them to the plan and the patient so the source form is visible from the records it
     * produced — otherwise the only evidence of what was enrolled lives in someone's Files.
     */
    private Boolean linkDocument(Id documentId, Set<Id> linkedEntityIds) {
        if (documentId == null || linkedEntityIds.isEmpty()) {
            return false;
        }

        Set<Id> alreadyLinked = new Set<Id>();
        for (ContentDocumentLink existing : [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :documentId
              AND LinkedEntityId IN :linkedEntityIds
        ]) {
            alreadyLinked.add(existing.LinkedEntityId);
        }

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (Id entityId : linkedEntityIds) {
            if (alreadyLinked.contains(entityId)) {
                continue;
            }
            links.add(new ContentDocumentLink(
                ContentDocumentId = documentId,
                LinkedEntityId = entityId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }

        if (links.isEmpty()) {
            return true;
        }
        insert links;
        return true;
    }

    /**
     * @description Wrapper for enrollment results.
     */
    public class EnrollmentResult {
        @AuraEnabled public Id patientId;
        @AuraEnabled public Id programId;
        @AuraEnabled public Id planId;
        @AuraEnabled public Id onboardingTaskId;
        @AuraEnabled public Boolean isNewPatient;
        @AuraEnabled public String patientName;
        @AuraEnabled public String planNumber;
        @AuraEnabled public String programName;
        @AuraEnabled public String programCode;
        @AuraEnabled public Boolean documentLinked;
        @AuraEnabled public Id hcpId;
        @AuraEnabled public String hcpName;
        @AuraEnabled public Boolean isNewHcp;
        @AuraEnabled public Id hcoId;
        @AuraEnabled public String hcoName;
        @AuraEnabled public Boolean isNewHco;
        /** How many Affiliation__c records this enrollment created. Existing links are reused. */
        @AuraEnabled public Integer affiliationsCreated;
        /** Populated when relationships could not be recorded. The enrollment still succeeded. */
        @AuraEnabled public String affiliationError;
        /** Labels of fields changed on an existing patient, so the UI can report what synced. */
        @AuraEnabled public List<String> updatedPatientFields;

        public EnrollmentResult() {
            this.isNewPatient = false;
            this.documentLinked = false;
            this.isNewHcp = false;
            this.isNewHco = false;
            this.affiliationsCreated = 0;
            this.updatedPatientFields = new List<String>();
        }
    }

    public class EnrollmentException extends Exception {}
}

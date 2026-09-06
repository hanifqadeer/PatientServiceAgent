/**
 * @description Orchestrates the full enrollment journey:
 *              1. Parse extracted data (from AI extraction)
 *              2. Validate the Care Program before touching any patient data
 *              3. Match or create the Patient, syncing reviewer edits onto an existing one
 *              4. Refuse a second open plan for the same program
 *              5. Create Patient Support Plan (PSP Case)
 *              6. Assign coordinator and create the onboarding Task
 *              7. Link the source enrollment document to the plan and the patient
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

    public EnrollmentService() {
        this.patientSvc = new PatientService();
        this.programSvc = new CareProgramService();
        this.planSvc = new PatientSupportPlanService();
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
        Care_Program__c program = programSvc.getProgramByCode(extraction.programCode);
        if (program == null) {
            throw new EnrollmentException(
                String.isBlank(extraction.programCode)
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

        // ── Step 3: Create Patient Support Plan ──
        Case psp = planSvc.createPlan(
            patient.Id,
            program.Id,
            extraction.enrollmentSource,
            null // Coordinator assigned below or later
        );
        result.planId = psp.Id;

        // ── Step 4: Activate Plan ──
        planSvc.activatePlan(psp.Id);

        // ── Step 5: Create Onboarding Task ──
        // For MVP, assign to the running user; coordinator assignment comes later
        Task onboarding = planSvc.createOnboardingTask(psp.Id, UserInfo.getUserId());
        result.onboardingTaskId = onboarding.Id;

        // ── Step 6: Link the source document ──
        result.documentLinked = linkDocument(documentId, new Set<Id>{ psp.Id, patient.Id });

        result.planNumber = [SELECT CaseNumber FROM Case WHERE Id = :psp.Id LIMIT 1].CaseNumber;
        return result;
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
        /** Labels of fields changed on an existing patient, so the UI can report what synced. */
        @AuraEnabled public List<String> updatedPatientFields;

        public EnrollmentResult() {
            this.isNewPatient = false;
            this.documentLinked = false;
            this.updatedPatientFields = new List<String>();
        }
    }

    public class EnrollmentException extends Exception {}
}

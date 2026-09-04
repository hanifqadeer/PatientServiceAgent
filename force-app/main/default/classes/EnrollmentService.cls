/**
 * @description Orchestrates the full enrollment journey:
 *              1. Parse extracted data (from AI extraction)
 *              2. Match or create Patient
 *              3. Validate Care Program eligibility
 *              4. Create Patient Support Plan (PSP Case)
 *              5. Assign coordinator
 *              6. Create onboarding Task
 *
 *              Single transaction boundary — if any step fails,
 *              the entire enrollment rolls back.
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
     * @param existingPatientId If a duplicate was selected, use this patient.
     *                          Null to create a new patient.
     * @return EnrollmentResult with the created/matched Patient and PSP.
     */
    public EnrollmentResult processEnrollment(EnrollmentExtractionResult extraction,
                                               Id existingPatientId) {
        if (extraction == null) {
            throw new EnrollmentException('Extraction data is required.');
        }

        EnrollmentResult result = new EnrollmentResult();

        // ── Step 1: Resolve Patient ──
        Account patient;
        if (existingPatientId != null) {
            // Use existing patient (user selected from duplicate matches)
            List<Account> existing = patientSvc.getPatients(new Set<Id>{ existingPatientId });
            if (existing.isEmpty()) {
                throw new EnrollmentException('Selected patient not found.');
            }
            patient = existing[0];
            result.isNewPatient = false;
        } else {
            // Create new patient from extraction data
            patient = patientSvc.createPatient(extraction);
            result.isNewPatient = true;
        }
        result.patientId = patient.Id;

        // ── Step 2: Validate Care Program ──
        Care_Program__c program = programSvc.getProgramByCode(extraction.programCode);
        if (program == null) {
            throw new EnrollmentException('Care Program not found with code: ' + extraction.programCode);
        }
        if (!programSvc.isProgramEligible(program.Id)) {
            throw new EnrollmentException('Care Program "' + program.Name + '" is not eligible for enrollment.');
        }
        result.programId = program.Id;

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

        return result;
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

        public EnrollmentResult() {
            this.isNewPatient = false;
        }
    }

    public class EnrollmentException extends Exception {}
}

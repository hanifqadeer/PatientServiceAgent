/**
 * @description Comprehensive test data factory for the Patient Services Hub.
 *              Creates realistic synthetic data for all domain objects.
 *              Bulk-capable — no hard-coded IDs.
 *              Used by all test classes to avoid test data duplication.
 */
@IsTest
public class TestDataFactory {

    // ── Record Type Ids (cached) ──
    private static Id patientRtId;
    private static Id hcpRtId;
    private static Id hcoRtId;
    private static Id pspRtId;
    private static Id accessRtId;
    private static Id supportRtId;
    private static Id coordRtId;

    static {
        Map<String, Schema.RecordTypeInfo> accountRts = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName();
        patientRtId = accountRts.get('Patient')?.getRecordTypeId();
        hcpRtId = accountRts.get('HCP')?.getRecordTypeId();
        hcoRtId = accountRts.get('HCO')?.getRecordTypeId();

        Map<String, Schema.RecordTypeInfo> caseRts = Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName();
        pspRtId = caseRts.get('Patient_Support_Plan')?.getRecordTypeId();
        accessRtId = caseRts.get('Access_Reimbursement')?.getRecordTypeId();
        supportRtId = caseRts.get('Patient_Support')?.getRecordTypeId();
        coordRtId = caseRts.get('Coordination')?.getRecordTypeId();
    }

    /**
     * @description Create Patient person accounts.
     */
    public static List<Account> createPatients(Integer count) {
        List<Account> patients = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            Account pat = new Account(
                FirstName = 'TestPatient' + i,
                LastName = 'User' + i,
                PersonBirthdate = Date.today().addYears(-30 - i),
                Phone = '(555) 100-' + String.valueOf(1000 + i),
                PersonEmail = 'patient' + i + '@test.example.com',
                Preferred_Language__c = 'English',
                Communication_Preference__c = 'Phone'
            );
            pat.put('RecordTypeId', patientRtId);
            patients.add(pat);
        }
        insert patients;
        return patients;
    }

    /**
     * @description Create HCP person accounts.
     */
    public static List<Account> createHCPs(Integer count) {
        List<Account> hcps = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            Account hcp = new Account(
                FirstName = 'Dr' + i,
                LastName = 'Provider' + i,
                NPI_Number__c = '100000000' + String.valueOf(i),
                Specialty__c = 'Oncology'
            );
            hcp.put('RecordTypeId', hcpRtId);
            hcps.add(hcp);
        }
        insert hcps;
        return hcps;
    }

    /**
     * @description Create HCO business accounts.
     */
    public static List<Account> createHCOs(Integer count) {
        List<Account> hcos = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            Account hco = new Account(
                Name = 'Test Hospital ' + i,
                Site_Type__c = 'Hospital',
                Tax_ID__c = 'TAX-' + String.valueOf(100000 + i)
            );
            hco.put('RecordTypeId', hcoRtId);
            hcos.add(hco);
        }
        insert hcos;
        return hcos;
    }

    /**
     * @description Create active Care Programs.
     */
    public static List<Care_Program__c> createCarePrograms(Integer count) {
        List<Care_Program__c> programs = new List<Care_Program__c>();
        for (Integer i = 0; i < count; i++) {
            programs.add(new Care_Program__c(
                Name = 'Test Program ' + i,
                Program_Code__c = 'TP-' + String.valueOf(1000 + i),
                Program_Type__c = 'Hub Services',
                Therapy_Area__c = 'Oncology',
                Product_Name__c = 'TestDrug' + i,
                Status__c = 'Active',
                Effective_Start_Date__c = Date.today().addMonths(-6),
                Effective_End_Date__c = Date.today().addMonths(12)
            ));
        }
        insert programs;
        return programs;
    }

    /**
     * @description Create Patient Support Plans (PSP Cases).
     */
    public static List<Case> createSupportPlans(List<Account> patients, Care_Program__c program) {
        List<Case> plans = new List<Case>();
        // Re-query to get PersonContactId
        Set<Id> patientIds = new Set<Id>();
        for (Account p : patients) { patientIds.add(p.Id); }
        Map<Id, Account> patientMap = new Map<Id, Account>([
            SELECT Id, PersonContactId FROM Account WHERE Id IN :patientIds
        ]);

        for (Account patient : patients) {
            Account fullPatient = patientMap.get(patient.Id);
            Case c = new Case(
                AccountId = patient.Id,
                ContactId = fullPatient?.PersonContactId,
                Care_Program__c = program.Id,
                Subject = 'PSP - ' + program.Name,
                Status = 'New',
                Priority = 'Medium',
                Enrollment_Source__c = 'Fax',
                Enrollment_Date__c = Date.today(),
                Support_Level__c = 'Standard'
            );
            c.put('RecordTypeId', pspRtId);
            plans.add(c);
        }
        insert plans;
        return plans;
    }

    /**
     * @description Create child support Cases under a parent PSP.
     */
    public static List<Case> createSupportCases(Case parentPlan, Integer count, String category) {
        String rtDevName = 'Patient_Support';
        if (category == 'Benefits Verification' || category == 'Prior Authorization'
            || category == 'Appeals' || category == 'Reimbursement') {
            rtDevName = 'Access_Reimbursement';
        } else if (category == 'Appointment' || category == 'Site of Care'
                   || category == 'Provider Coordination') {
            rtDevName = 'Coordination';
        }

        Id rtId = Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get(rtDevName)
            .getRecordTypeId();

        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < count; i++) {
            Case c = new Case(
                ParentId = parentPlan.Id,
                AccountId = parentPlan.AccountId,
                ContactId = parentPlan.ContactId,
                Subject = category + ' Case ' + i,
                Status = 'New',
                Priority = 'Medium',
                Support_Category__c = category
            );
            c.put('RecordTypeId', rtId);
            cases.add(c);
        }
        insert cases;
        return cases;
    }

    /**
     * @description Create Tasks related to a Case.
     */
    public static List<Task> createTasks(Id whatId, Integer count) {
        List<Task> tasks = new List<Task>();
        for (Integer i = 0; i < count; i++) {
            tasks.add(new Task(
                WhatId = whatId,
                Subject = 'Test Task ' + i,
                Status = 'Not Started',
                Priority = 'Normal',
                ActivityDate = Date.today().addDays(i + 1)
            ));
        }
        insert tasks;
        return tasks;
    }

    /**
     * @description Create Events related to a Case.
     */
    public static List<Event> createEvents(Id whatId, Integer count) {
        List<Event> events = new List<Event>();
        for (Integer i = 0; i < count; i++) {
            events.add(new Event(
                WhatId = whatId,
                Subject = 'Test Event ' + i,
                StartDateTime = Datetime.now().addDays(i + 1),
                EndDateTime = Datetime.now().addDays(i + 1).addHours(1),
                Location = 'Test Location ' + i
            ));
        }
        insert events;
        return events;
    }

    /**
     * @description Create Affiliations between accounts.
     */
    public static List<Affiliation__c> createAffiliations(Account primary, List<Account> secondaries, String affiliationType) {
        List<Affiliation__c> affiliations = new List<Affiliation__c>();
        for (Account secondary : secondaries) {
            affiliations.add(new Affiliation__c(
                Account_1__c = primary.Id,
                Account_2__c = secondary.Id,
                Affiliation_Type__c = affiliationType,
                Role__c = 'Prescriber',
                Is_Primary__c = (affiliations.isEmpty()),
                Status__c = 'Active',
                Effective_Start_Date__c = Date.today()
            ));
        }
        insert affiliations;
        return affiliations;
    }

    /**
     * @description Create a complete mock EnrollmentExtractionResult.
     */
    public static EnrollmentExtractionResult createMockExtraction(String programCode) {
        EnrollmentExtractionResult result = AIExtractionMock.getMockExtraction();
        if (String.isNotBlank(programCode)) {
            result.programCode = programCode;
        }
        return result;
    }
}

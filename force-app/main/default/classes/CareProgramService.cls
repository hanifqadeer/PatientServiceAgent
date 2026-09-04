/**
 * @description Service for Care Program operations.
 *              Query active programs and validate program eligibility.
 *              Bulk-safe, runs with sharing.
 */
public with sharing class CareProgramService {

    /**
     * @description Get all active Care Programs.
     * @return List of active Care Programs.
     */
    public List<Care_Program__c> getActivePrograms() {
        return [
            SELECT Id, Name, Program_Code__c, Description__c,
                   Program_Type__c, Therapy_Area__c, Product_Name__c,
                   Status__c, Effective_Start_Date__c, Effective_End_Date__c
            FROM Care_Program__c
            WHERE Status__c = 'Active'
            ORDER BY Name ASC
        ];
    }

    /**
     * @description Get a specific program by its unique code.
     * @param programCode The program code to look up.
     * @return The matching Care Program, or null if not found.
     */
    public Care_Program__c getProgramByCode(String programCode) {
        if (String.isBlank(programCode)) {
            return null;
        }
        List<Care_Program__c> programs = [
            SELECT Id, Name, Program_Code__c, Description__c,
                   Program_Type__c, Therapy_Area__c, Product_Name__c,
                   Status__c, Effective_Start_Date__c, Effective_End_Date__c
            FROM Care_Program__c
            WHERE Program_Code__c = :programCode
            LIMIT 1
        ];
        return programs.isEmpty() ? null : programs[0];
    }

    /**
     * @description Validate that a program is eligible for new enrollments.
     *              Program must be Active and within its effective date range.
     * @param programId The Care Program Id.
     * @return true if eligible, false otherwise.
     */
    public Boolean isProgramEligible(Id programId) {
        if (programId == null) {
            return false;
        }
        List<Care_Program__c> programs = [
            SELECT Id, Status__c, Effective_Start_Date__c, Effective_End_Date__c
            FROM Care_Program__c
            WHERE Id = :programId
            LIMIT 1
        ];
        if (programs.isEmpty()) {
            return false;
        }
        Care_Program__c prog = programs[0];
        if (prog.Status__c != 'Active') {
            return false;
        }
        Date today = Date.today();
        if (prog.Effective_Start_Date__c != null && today < prog.Effective_Start_Date__c) {
            return false;
        }
        if (prog.Effective_End_Date__c != null && today > prog.Effective_End_Date__c) {
            return false;
        }
        return true;
    }
}

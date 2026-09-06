/**
 * @description Match-or-create for the two parties on an enrollment form that are not the
 *              patient: the prescribing provider (HCP) and the treatment facility (HCO).
 *
 *              Same discipline as patient matching — a prescriber who appears on fifty
 *              enrollment forms should be one Account, not fifty. Matching prefers an
 *              identifier over a name: NPI for a provider, tax ID for a facility. Names are
 *              the fallback, because two clinics can share one.
 *
 *              Per the architecture data model, HCP is a Person Account record type and HCO is
 *              a Business Account record type.
 */
public with sharing class ProviderService {
    private static final String HCP_RT = 'HCP';
    private static final String HCO_RT = 'HCO';

    /** Result of a match-or-create, so callers can report what was reused versus created. */
    public class ProviderResult {
        public Account record;
        public Boolean isNew;

        private ProviderResult(Account record, Boolean isNew) {
            this.record = record;
            this.isNew = isNew;
        }
    }

    /**
     * @description Find the prescribing provider named on the form, or create them.
     * @param extraction The reviewed extraction data.
     * @return The provider, or null when the form named nobody usable.
     */
    public ProviderResult findOrCreateHcp(EnrollmentExtractionResult extraction) {
        if (extraction == null || String.isBlank(extraction.hcpLastName)) {
            // Without a surname there is nothing to match on and nothing worth creating.
            return null;
        }

        Account existing = findHcp(extraction.hcpNpi, extraction.hcpFirstName, extraction.hcpLastName);
        if (existing != null) {
            return new ProviderResult(existing, false);
        }

        Account hcp = new Account(
            FirstName = extraction.hcpFirstName,
            LastName = extraction.hcpLastName,
            NPI_Number__c = extraction.hcpNpi,
            Specialty__c = extraction.hcpSpecialty
        );
        hcp.put('RecordTypeId', recordTypeId(HCP_RT));
        insert hcp;
        return new ProviderResult(hcp, true);
    }

    /**
     * @description Find the treatment facility named on the form, or create it.
     * @param extraction The reviewed extraction data.
     * @return The facility, or null when the form named none.
     */
    public ProviderResult findOrCreateHco(EnrollmentExtractionResult extraction) {
        if (extraction == null || String.isBlank(extraction.hcoName)) {
            return null;
        }

        Account existing = findHco(extraction.hcoTaxId, extraction.hcoName);
        if (existing != null) {
            return new ProviderResult(existing, false);
        }

        Account hco = new Account(
            Name = extraction.hcoName,
            Site_Type__c = extraction.hcoSiteType,
            Tax_ID__c = extraction.hcoTaxId
        );
        hco.put('RecordTypeId', recordTypeId(HCO_RT));
        insert hco;
        return new ProviderResult(hco, true);
    }

    /**
     * NPI first: it identifies a provider nationally, so a match on it is definitive and
     * survives a name spelled differently on two forms. Name matching is the fallback for the
     * common case of a fax where the NPI was illegible — the prompt returns null rather than a
     * half-read number, so this path runs more often than it might seem.
     */
    private Account findHcp(String npi, String firstName, String lastName) {
        if (String.isNotBlank(npi)) {
            List<Account> byNpi = [
                SELECT Id, FirstName, LastName, NPI_Number__c, Specialty__c
                FROM Account
                WHERE NPI_Number__c = :npi
                  AND RecordType.DeveloperName = :HCP_RT
                LIMIT 1
            ];
            if (!byNpi.isEmpty()) {
                return byNpi[0];
            }
        }

        if (String.isBlank(firstName)) {
            // A surname alone is too weak to merge two providers on.
            return null;
        }
        List<Account> byName = [
            SELECT Id, FirstName, LastName, NPI_Number__c, Specialty__c
            FROM Account
            WHERE LastName = :lastName
              AND FirstName = :firstName
              AND RecordType.DeveloperName = :HCP_RT
            LIMIT 1
        ];
        return byName.isEmpty() ? null : byName[0];
    }

    private Account findHco(String taxId, String name) {
        if (String.isNotBlank(taxId)) {
            List<Account> byTaxId = [
                SELECT Id, Name, Site_Type__c, Tax_ID__c
                FROM Account
                WHERE Tax_ID__c = :taxId
                  AND RecordType.DeveloperName = :HCO_RT
                LIMIT 1
            ];
            if (!byTaxId.isEmpty()) {
                return byTaxId[0];
            }
        }

        List<Account> byName = [
            SELECT Id, Name, Site_Type__c, Tax_ID__c
            FROM Account
            WHERE Name = :name
              AND RecordType.DeveloperName = :HCO_RT
            LIMIT 1
        ];
        return byName.isEmpty() ? null : byName[0];
    }

    private Id recordTypeId(String developerName) {
        Schema.RecordTypeInfo info = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get(developerName);
        if (info == null) {
            throw new ProviderServiceException(
                'The ' + developerName + ' Account record type is missing from this org.'
            );
        }
        return info.getRecordTypeId();
    }

    public class ProviderServiceException extends Exception {}
}

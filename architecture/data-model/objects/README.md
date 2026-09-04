# Object Catalogue

## Standard

-   **Account / Patient Person Account**
-   **Account / HCP Person Account**
-   **Account / HCO Business Account**
-   **Case** --- Support Case.
-   **Task** --- actionable work.
-   **Event** --- scheduled/time-bound interaction.
-   **Salesforce Files** --- enrollment/support documents.
-   **User** --- internal ownership/assignment.

## Custom: Care_Program\_\_c

Master program definition. Candidate fields: Name, Program Code,
Description, Program Type, Therapy/Product context, Status and general
effective/availability information.

Do not store patient-specific enrollment dates here.

## Custom: Patient_Support_Plan\_\_c

Patient-specific participation and operational context. Candidate
fields: Patient, Care Program, Status, Start Date, End Date, Primary
Care Coordinator, Enrollment Source, Support Level, Last/Next Review
Date, Completion/Discontinuation Reason.

## Relationship Objects

Exact standard-vs-custom choice remains an ADR: - Patient-HCP
Relationship. - HCP-HCO Affiliation.

Possible relationship attributes: type, role, primary indicator,
effective dates, status.

Do not add real-world pharma fields merely to make the schema look
large. Add what the demo journeys require.

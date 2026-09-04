# Patient Services Hub — Build Walkthrough

## What Was Built

A complete **Salesforce DX metadata project** implementing an AI-powered Pharma Patient Services Hub across 10 phases.

---

## Phase Summary

### Phase 2 — Data Model
| Metadata | Files |
|---|---|
| Account Record Types | `Patient`, `HCP`, `HCO` |
| Account Custom Fields | `Preferred_Language__c`, `Communication_Preference__c`, `NPI_Number__c`, `Specialty__c`, `Site_Type__c`, `Tax_ID__c` |
| Care_Program__c Object | 8 fields: Program_Code__c, Description__c, Program_Type__c, Therapy_Area__c, Product_Name__c, Status__c, dates |
| Case Record Types | `Patient_Support_Plan`, `Access_Reimbursement`, `Patient_Support`, `Coordination` |
| Case Custom Fields | 15 fields covering lifecycle, program linkage, coordinator, payer, category |
| Affiliation__c Object | M:M junction (ADR-008/009): Account_1__c, Account_2__c, Role__c, Is_Primary__c, Status__c, dates |

### Phase 3 — Tabs
- `Care_Program__c.tab-meta.xml`
- `Affiliation__c.tab-meta.xml`

### Phase 4 — Apex Architecture

Follows strict `LWC → Controller → Service → Selector → Salesforce` layering.

```
DTOs
├── EnrollmentExtractionResult  — AI extraction output (patient, HCP, HCO, program, payer, confidence scores)
└── SupportSummaryResult        — Grounded plan summary (metrics, flags)

Selector
└── PatientSelector             — Centralized SOQL for Patient accounts

Services
├── PatientService              — Patient CRUD, duplicate detection
├── CareProgramService          — Active programs, eligibility validation
├── PatientSupportPlanService   — PSP lifecycle: create, activate, complete, discontinue, onboarding task
├── SupportCaseService          — Child case creation with category-based RT routing, escalation, resolve
├── AIExtractionService         — Facade (delegates to mock; swap-ready for real AI)
├── AIExtractionMock            — Synthetic data: realistic complete + incomplete scenarios
├── AISummaryService            — Deterministic grounded summary (no LLM)
└── EnrollmentService           — Orchestrator: patient → program → PSP → activate → onboarding task

Controllers (thin @AuraEnabled boundaries)
├── EnrollmentController        — extractFromDocument, searchDuplicatePatients, getActivePrograms, confirmEnrollment
└── PatientSummaryController    — getPatientSummary (360), getPlanSummary (AI summary)
```

### Phase 5 — LWC Components

| Component | Purpose |
|---|---|
| `enrollmentFileUpload` | Drag-and-drop document upload; fires documentId to parent |
| `careProgramSelector` | Searchable active program picker with hover selection |
| `enrollmentReview` | **Primary custom LWC** — 3-step wizard: Upload → Review/Edit → Success |
| `patientSummary` | Patient 360 coordinator view: header, AI summary, plans, cases, affiliations, quick actions |
| `supportPlanTimeline` | Chronological merge of Cases + Tasks + Events with status color coding |

#### Enrollment Review Wizard Detail
- **Step 1 — Upload**: `enrollmentFileUpload` triggers AI extraction
- **Step 2 — Review**: Editable fields per section (Patient, HCP, Program, Payer) with color-coded confidence badges (🟢 ≥90%, 🟡 ≥60%, 🔴 <60%), warning banner, duplicate patient datatable
- **Step 3 — Success**: Confirmation with new/existing patient indicator

### Phase 6 — Flows

| Flow | Type | Purpose |
|---|---|---|
| `Case_Closure_Validation` | Before-Save | Prevents Case closure without `Resolution_Summary__c` |
| `Support_Case_High_Priority_Routing` | After-Save (Create) | Auto-creates urgent follow-up Task for High-priority PA/Appeals cases |

### Phase 7 — Permission Sets

| Permission Set | Role | Key Access |
|---|---|---|
| `Enrollment_Specialist` | Enrollment intake | Read programs, create patients + PSPs, limited case fields |
| `Care_Coordinator` | Core operational role | Full plan/case lifecycle, affiliations, coordinator assignment |
| `Care_Coordinator_Manager` | Supervisory | Broad read, can reassign coordinators, edit escalated cases |
| `Field_Reimbursement_Manager` | FRM | Access & Reimbursement cases only; cannot edit plan fields |

### Phase 8 — Lightning App & Flexipages

- **`Patient_Services_Hub`** Lightning App — navigation: Home, Patients, Care Programs, Cases, Affiliations, Reports
- **`Patient_Record_Page`** — `patientSummary` LWC in main region
- **`Patient_Support_Plan_Record_Page`** — record detail + `supportPlanTimeline` LWC
- **`Enrollment_App_Page`** — full-width `enrollmentReview` LWC
- **`Care_Program_Record_Page`** — record detail with related plans

### Phase 9 — Mock Data
- `MockEnrollmentData.json` — 2 realistic enrollment scenarios (Oncology / Rheumatology) used by LWC demo

### Phase 10 — Tests

| Test Class | Coverage Focus |
|---|---|
| `TestDataFactory` | All domain objects, bulk-capable, no hard-coded IDs |
| `PatientServiceTest` | Duplicate detection, patient creation, error cases |
| `CareProgramServiceTest` | Active programs, code lookup, eligibility (active/closed) |
| `PatientSupportPlanServiceTest` | Create, activate, complete, discontinue, onboarding task |
| `SupportCaseServiceTest` | All 3 RT routing paths, escalation, resolve, bulk child query |
| `EnrollmentServiceTest` | Full journey, existing patient, closed/missing program |
| `EnrollmentControllerTest` | All @AuraEnabled methods, AuraHandledException |
| `PatientSummaryControllerTest` | 360 aggregation, open case counting, error cases |
| `AIExtractionServiceTest` | Complete/incomplete mock, DTO defaults |
| `AISummaryServiceTest` | Summary text, attention flags, overdue tasks, error cases |

---

## Architecture Compliance

| ADR | Compliance |
|---|---|
| ADR-001: Standard-first | Cases as service execution engine, standard Account for Patient/HCP |
| ADR-008/009: M:M affiliations | `Affiliation__c` junction object |
| ADR-010: Human-in-the-loop AI | Extraction → human review/edit → confirm → create records |
| Security: FLS/CRUD | All Apex runs `with sharing`; field permissions per permission set |
| AI guardrails | No diagnosis/prescribing; summaries are grounded deterministic text |
| Layer pattern | `LWC → Controller → Service → Selector → Salesforce` strictly maintained |

---

## Deployment Prerequisites

> [!IMPORTANT]
> Before deploying, ensure the following org configuration is in place:

1. **Enable Person Accounts** in Setup → Account Settings
2. **Deploy** with `sf project deploy start --source-dir force-app`
3. **Assign Permission Sets** to users by persona
4. **Activate Flexipages** in Lightning App Builder and set as org/app defaults
5. **Create at least one Care Program** record to demo enrollment flow

## Demo Flow

1. Open **Patient Services Hub** app → click **New Enrollment** (Enrollment App Page)
2. Upload any PDF — AI extraction auto-populates all fields with mock data
3. Review confidence badges, edit any field, check for duplicate patients
4. Click **Confirm Enrollment** → Patient + PSP + onboarding Task created
5. Navigate to the new Patient record → **Patient 360 Summary** LWC shows all data
6. Click any Support Plan → **Timeline** shows Cases, Tasks, Events in chronological order

# Full Build: AI-Powered Pharma Patient Services Hub

Build the complete Salesforce application described in the architecture documents as a deployable SFDX project.

## User Review Required

> [!IMPORTANT]
> **Scope**: This plan builds out the full MVP as a Salesforce DX metadata project. It will contain real deployable metadata (objects, fields, Apex, LWC, Flows, permission sets, layouts, tabs) plus synthetic test data factories. The project can be deployed to any Salesforce org with Person Accounts enabled.

> [!WARNING]
> **Person Accounts**: The architecture requires Person Accounts (Patient, HCP as Person Accounts). Person Accounts must be enabled in the target org — this cannot be done via metadata deployment. The metadata will be structured to work with Person Accounts but this org feature must be enabled manually.

> [!IMPORTANT]
> **AI Features**: Real OCR/LLM integration requires Salesforce Einstein or an external AI API. This build will create the full AI extraction review flow with a **simulated extraction service** (mock JSON responses) so the entire workflow is demonstrable end-to-end without requiring AI API keys. The architecture is wired so the mock can be swapped for a real AI service later.

## Open Questions

1. **Target Salesforce Edition** — Do you have a specific Salesforce org/edition in mind (Developer Edition, Enterprise trial, etc.)? This affects available features. Plan assumes Developer Edition with Person Accounts.
2. **AI Simulation vs Real** — Should AI extraction use a hardcoded mock, or do you have access to an Einstein/OpenAI API key to wire up real extraction?
3. **Integration Target** — The architecture says "one meaningful REST integration, TBD." Should I pick a relevant external API (e.g., NPI Registry for HCP lookup, or OpenFDA for drug info), or leave it as a mock integration pattern?

---

## Proposed Changes

### Phase 1: SFDX Project Scaffolding

Set up the Salesforce DX project structure with `sfdx-project.json`, directory layout, and configuration.

#### [NEW] `sfdx-project.json`
Standard SFDX project descriptor pointing to `force-app/main/default`.

#### [NEW] `.forceignore`
Ignore patterns for deployment.

#### [NEW] `force-app/main/default/` directory structure
```
force-app/main/default/
├── objects/
├── classes/
├── lwc/
├── flows/
├── permissionsets/
├── layouts/
├── tabs/
├── flexipages/
├── quickActions/
├── reports/
├── dashboards/
└── staticresources/
```

---

### Phase 2: Data Model — Custom Objects & Fields (Epics 1–3)

Build the complete domain model per the architecture data-model docs and ADR register.

#### [NEW] `force-app/main/default/objects/Account/recordTypes/`
- `Patient.recordType-meta.xml` — Person Account record type for Patients
- `HCP.recordType-meta.xml` — Person Account record type for Healthcare Providers
- `HCO.recordType-meta.xml` — Business Account record type for Healthcare Organizations

#### [NEW] `force-app/main/default/objects/Account/fields/`
Custom fields on Account for the pharma domain:
- `Preferred_Language__c` (Picklist)
- `Communication_Preference__c` (Picklist: Phone, Email, Mail, Portal)
- `NPI_Number__c` (Text — HCP identifier)
- `Specialty__c` (Picklist — HCP specialty)
- `Site_Type__c` (Picklist — HCO: Hospital, Clinic, Pharmacy, Infusion Center)
- `Tax_ID__c` (Text — HCO identifier)

#### [NEW] `force-app/main/default/objects/Care_Program__c/`
Custom object: master program definition.
- `Care_Program__c.object-meta.xml`
- **Fields**: Name (auto), `Program_Code__c` (Text, unique, external ID), `Description__c` (Long Text Area), `Program_Type__c` (Picklist: Commercial Copay, Free Drug, Bridge, Hub Services), `Therapy_Area__c` (Text), `Product_Name__c` (Text), `Status__c` (Picklist: Draft, Active, Suspended, Closed), `Effective_Start_Date__c` (Date), `Effective_End_Date__c` (Date)

#### [REVISED] Patient Support Plan → Standard Case Record Type
Instead of a custom object, Patient Support Plan is modeled as a **Case record type**. All service requests (Benefits Verification, Prior Auth, etc.) are **child Cases** under the parent PSP Case using the standard `ParentId` field. This leverages native Case hierarchy, ownership, queues, escalation, and reporting.

**Case Record Types:**
- `Patient_Support_Plan` — the parent plan Case
- `Access_Reimbursement` — child: BV, PA, Appeals, Reimbursement
- `Patient_Support` — child: Education, Program Question, General Assistance
- `Coordination` — child: Appointment, Site of Care, Provider Coordination

**Custom fields on Case** (for PSP record type):
- `Care_Program__c` (Lookup → Care_Program__c)
- `Primary_Care_Coordinator__c` (Lookup → User)
- `Enrollment_Source__c` (Picklist: Fax, eForm, Phone, HCP Referral, Web)
- `Support_Level__c` (Picklist: Standard, High-Touch, Lite)
- `Enrollment_Date__c` (Date)
- `Plan_Start_Date__c` (Date)
- `Plan_End_Date__c` (Date)
- `Last_Review_Date__c` (Date)
- `Next_Review_Date__c` (Date)
- `Completion_Reason__c` (Text Area)
- `Discontinuation_Reason__c` (Text Area)

**Custom fields on Case** (for service request record types):
- `Support_Category__c` (Picklist)
- `Support_Subcategory__c` (Text)
- `Resolution_Summary__c` (Long Text Area)
- `External_Reference_Number__c` (Text)

#### [NEW] `force-app/main/default/objects/Affiliation__c/`
Single unified junction object for **all** party relationships: Patient↔HCP, HCP↔HCO, and any future affiliations.
- **Fields**: `Account_1__c` (Master-Detail → Account), `Account_2__c` (Lookup → Account), `Affiliation_Type__c` (Picklist: Patient-HCP, HCP-HCO), `Role__c` (Picklist: Prescriber, Referring, Treating, Consulting, Staff Physician, Affiliated, Admitting), `Is_Primary__c` (Checkbox), `Effective_Start_Date__c` (Date), `Effective_End_Date__c` (Date), `Status__c` (Picklist: Active, Inactive)

#### Case fields
All custom fields described above under the revised Patient Support Plan model are created as fields on the standard Case object.

#### Task / Event fields
No additional custom lookup needed — Tasks and Events relate to Cases natively via `WhatId`. The parent PSP Case serves as the container.

#### [NEW] Tabs for custom objects
- `Care_Program__c.tab-meta.xml`
- `Affiliation__c.tab-meta.xml`

---

### Phase 3: Case Model & Lifecycle (Epic 4)

#### [NEW] `force-app/main/default/objects/Case/recordTypes/`
- `Access_Reimbursement.recordType-meta.xml`
- `Patient_Support.recordType-meta.xml`
- `Coordination.recordType-meta.xml`

#### [NEW] Case Status values (via `Case.object-meta.xml` or `standardValueSets/`)
Lifecycle: `New → In Progress → Waiting on External Party → Resolved → Closed`

#### [NEW] `force-app/main/default/layouts/`
- `Case-Access_Reimbursement_Layout.layout-meta.xml`
- `Case-Patient_Support_Layout.layout-meta.xml`
- `Case-Coordination_Layout.layout-meta.xml`
- `Patient_Support_Plan__c-Patient_Support_Plan_Layout.layout-meta.xml`
- `Care_Program__c-Care_Program_Layout.layout-meta.xml`

---

### Phase 4: Apex Services & Controllers (Epics 6–8)

Layered Apex following: `LWC → Controller → Service → Selector/Data Access`

#### [NEW] `force-app/main/default/classes/PatientService.cls`
Reusable patient operations: search/match patients by name/DOB, create Patient person account, find duplicates.

#### [NEW] `force-app/main/default/classes/PatientSelector.cls`
Centralized patient queries: by Id, by name+DOB, by external Id, with related plans.

#### [NEW] `force-app/main/default/classes/CareProgramService.cls`
Query active programs, validate program eligibility for enrollment.

#### [NEW] `force-app/main/default/classes/PatientSupportPlanService.cls`
Create/activate/complete/discontinue plans. Assign coordinator. Create onboarding tasks. Bulk-safe.

#### [NEW] `force-app/main/default/classes/SupportCaseService.cls`
Create cases linked to support plans. Route by category. Escalation logic. Resolve/close with summary.

#### [NEW] `force-app/main/default/classes/EnrollmentService.cls`
Orchestrates the enrollment journey: parse extracted data → match/create patient → validate program → create plan → assign coordinator → create onboarding task. Single transaction boundary.

#### [NEW] `force-app/main/default/classes/EnrollmentController.cls`
`@AuraEnabled` methods for the Enrollment Review LWC. Thin — delegates to `EnrollmentService`.

#### [NEW] `force-app/main/default/classes/PatientSummaryController.cls`
`@AuraEnabled` methods for Patient 360 summary LWC. Returns aggregated plan/case/task/event data.

#### [NEW] `force-app/main/default/classes/AIExtractionService.cls`
Simulated AI extraction service. Takes a file/document reference, returns structured enrollment data (patient name, DOB, HCP, program, etc.) as a wrapper class. Mock implementation returns synthetic data. Interface designed for future real AI swap-in.

#### [NEW] `force-app/main/default/classes/AIExtractionMock.cls`
Mock implementation returning realistic synthetic extraction results for demo.

#### [NEW] `force-app/main/default/classes/AISummaryService.cls`
Generates grounded support summaries from Plan, Cases, Tasks, Events. Deterministic (no LLM) — formats trusted data into a readable summary. Architecture-compliant: "ground in trusted data."

#### [NEW] `force-app/main/default/classes/IntegrationService.cls`
REST callout pattern using Named Credentials. GET/POST with proper error handling, timeout, logging. Callout-ready for NPI Registry or similar.

#### [NEW] `force-app/main/default/classes/IntegrationCalloutMock.cls`
`HttpCalloutMock` implementation for tests.

#### [NEW] Trigger handlers (if needed)
- `PatientSupportPlanTriggerHandler.cls` — coordinator assignment confirmation, onboarding task automation on plan activation.

---

### Phase 5: Lightning Web Components (Epics 6–8)

#### [NEW] `force-app/main/default/lwc/enrollmentReview/`
Primary custom LWC — the enrollment specialist's workspace:
- File upload area
- Extracted data display (editable fields: patient info, HCP, program)
- Duplicate patient match results
- Confidence indicators per extracted field
- Confirm / Edit / Reject actions
- Error handling for incomplete/ambiguous extractions

Files: `enrollmentReview.html`, `enrollmentReview.js`, `enrollmentReview.css`, `enrollmentReview.js-meta.xml`

#### [NEW] `force-app/main/default/lwc/patientSummary/`
Patient 360 summary component for the coordinator:
- Active Support Plans list with status badges
- AI-generated support summary (grounded)
- Recent Cases, Tasks, Events timeline
- Related HCPs/HCOs
- Quick action buttons (New Case, New Task, Log Event)

Files: `patientSummary.html`, `patientSummary.js`, `patientSummary.css`, `patientSummary.js-meta.xml`

#### [NEW] `force-app/main/default/lwc/supportPlanTimeline/`
Timeline view of all activity under a Support Plan:
- Cases, Tasks, Events in chronological order
- Status color coding
- Expandable detail cards

Files: `supportPlanTimeline.html`, `supportPlanTimeline.js`, `supportPlanTimeline.css`, `supportPlanTimeline.js-meta.xml`

#### [NEW] `force-app/main/default/lwc/careProgramSelector/`
Reusable program picker (used in enrollment flow):
- Search active programs
- Display program details
- Select and confirm

Files: `careProgramSelector.html`, `careProgramSelector.js`, `careProgramSelector.css`, `careProgramSelector.js-meta.xml`

#### [NEW] `force-app/main/default/lwc/enrollmentFileUpload/`
File upload component with drag-and-drop, tied to enrollment flow.

---

### Phase 6: Automation — Flows (Epic 6)

#### [NEW] `force-app/main/default/flows/Support_Case_High_Priority_Routing.flow-meta.xml`
Record-triggered Flow on Case: when a new Case has Priority = High and Support_Category = 'Prior Authorization' or 'Appeals', auto-assign to a specific queue and create a follow-up Task.

#### [NEW] `force-app/main/default/flows/Plan_Activation_Onboarding.flow-meta.xml`
Record-triggered Flow on Patient_Support_Plan__c: when Status changes to 'Active', create an onboarding Task assigned to the Primary Care Coordinator, send a confirmation notification.

#### [NEW] `force-app/main/default/flows/Case_Closure_Validation.flow-meta.xml`
Before-save Flow on Case: require `Resolution_Summary__c` when Status = 'Closed'.

---

### Phase 7: Security Model (Epic 5)

#### [NEW] `force-app/main/default/permissionsets/`
- `Enrollment_Specialist.permissionset-meta.xml` — CRUD on Patient, Care Program (Read), Patient Support Plan (Create/Read), Files, limited Case access
- `Care_Coordinator.permissionset-meta.xml` — Full CRUD on assigned Plans, Cases, Tasks, Events, Files, read HCP/HCO
- `Care_Coordinator_Manager.permissionset-meta.xml` — Read all Plans/Cases for reporting, edit escalated Cases, run reports/dashboards
- `Field_Reimbursement_Manager.permissionset-meta.xml` — Read/Edit Access & Reimbursement Cases assigned to them, read Plan context (not full plan edit), create Tasks/Events

#### [NEW] Security demo scenario
Two personas (Care Coordinator vs FRM) with different record-level access — coordinator sees full plan, FRM sees only the access cases they're involved in.

---

### Phase 8: Lightning Pages & UX (Epic 7)

#### [NEW] `force-app/main/default/flexipages/`
- `Patient_Record_Page.flexipage-meta.xml` — Patient 360 with `patientSummary` LWC, related plans, relationships, files
- `Patient_Support_Plan_Record_Page.flexipage-meta.xml` — Plan details + `supportPlanTimeline` LWC + related cases
- `Enrollment_App_Page.flexipage-meta.xml` — Full-page `enrollmentReview` LWC for enrollment specialists
- `Care_Program_Record_Page.flexipage-meta.xml` — Program details + related plans

#### [NEW] `force-app/main/default/applications/`
- `Patient_Services_Hub.app-meta.xml` — Lightning App with tabs: Home, Patients, Care Programs, Support Plans, Cases, Enrollment, Reports

---

### Phase 9: AI Features (Epic 9)

#### [NEW] `force-app/main/default/classes/EnrollmentExtractionResult.cls`
Wrapper/DTO class for AI extraction output: patient name, DOB, address, phone, HCP name, HCP NPI, HCO name, program indicator, therapy, payer info, confidence scores per field.

#### [NEW] `force-app/main/default/classes/SupportSummaryResult.cls`
Wrapper for AI summary output: summary text, key metrics (open cases count, overdue tasks, next event), attention flags.

#### [NEW] `force-app/main/default/staticresources/MockEnrollmentData.resource-meta.xml`
Synthetic enrollment form data (JSON) for demo extraction.

---

### Phase 10: Testing & Synthetic Data (Epic 10)

#### [NEW] `force-app/main/default/classes/TestDataFactory.cls`
Comprehensive test data factory: create Patients, HCPs, HCOs, Care Programs, Support Plans, Cases, Tasks, Events, relationships, affiliations. Bulk-capable.

#### [NEW] Test Classes (one per service/controller)
- `PatientServiceTest.cls` — positive, negative, bulk, duplicate detection
- `CareProgramServiceTest.cls` — active programs, eligibility
- `PatientSupportPlanServiceTest.cls` — create, activate, complete, discontinue, coordinator assignment
- `SupportCaseServiceTest.cls` — create, route, escalate, resolve, close validation
- `EnrollmentServiceTest.cls` — full enrollment journey, partial data, invalid program, duplicate patient
- `EnrollmentControllerTest.cls` — AuraEnabled method coverage
- `PatientSummaryControllerTest.cls` — summary data aggregation
- `AIExtractionServiceTest.cls` — mock extraction, error handling
- `AISummaryServiceTest.cls` — grounded summary generation
- `IntegrationServiceTest.cls` — callout mock, error codes, timeout handling
- `SecurityTest.cls` — demonstrate different persona access levels

> [!TIP]
> All tests will follow the architecture rules: positive + negative + bulk + missing-data + security scenarios. Test data created via `TestDataFactory` — no hard-coded IDs.

---

## Verification Plan

### Automated Tests
- All Apex classes will have companion `*Test.cls` files
- Target: 90%+ code coverage across all classes
- Run: `sf project deploy start --test-level RunLocalTests` to validate deployment + tests

### Manual Verification
- Deploy to a Developer Edition org with Person Accounts
- Walk through Enrollment Journey end-to-end
- Walk through Ongoing Support Journey
- Verify permission set differences between Care Coordinator and FRM
- Verify Flow triggers (high-priority case routing, plan activation onboarding)

### File Count Estimate
~80–100 files total across metadata, Apex, LWC, Flows, permissions, and layouts.

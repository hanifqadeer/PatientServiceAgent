# Patient Services Hub: code review and UI validation

Reviewed 6 September 2026 against the working copy, including the AI extraction changes, and the configured `PatientServicesHanif` Developer Edition org. During the review, those changes were committed externally as `da94d3a` and the prompt metadata was refreshed; the final source check accounts for that update.

**Assessment: enrollment is demonstrable in the deployed org, but the complete MVP is not ready.** The browser journey successfully created a synthetic patient, support plan and onboarding task. Ongoing support, permissions, information retention and reproducible deployment have material gaps.

## Verification and limits

| Check | Result |
| --- | --- |
| Source review | 29 Apex files, including 12 test classes; 5 LWC bundles; 2 Flows; 4 permission sets; domain metadata; 26 architecture notes and root plans |
| Working-copy snapshot: full check-only deployment with RunLocalTests | **Failed: 80 passed, 1 failed, 0 component errors**, 81 tests run; validation ID `0Afg800000CWI9NCAX`. This preceded the final prompt-metadata refresh. |
| Failure diagnosis | A temporary copy changed only the summary exception wrapper to rethrow the original exception. A second check-only deployment reproduced `No such column 'Role__c' on entity 'Affiliation__c'` at `PatientSummaryController:55`. The field exists in Tooling API; querying FieldPermissions returned no grants for it. |
| LWC unit test command | Could not run: `sfdx-lwc-jest` is not installed in this checkout. No LWC test files exist in source. |
| Lint command | Could not run: `eslint` is not installed in this checkout. |
| Browser validation | Authenticated Edge session against the deployed org; synthetic reference PDF; actual UI upload, extraction, edits, confirmation, record navigation and status editor inspection |
| Deployment changes | Both validations were check-only. Application source and org configuration were not changed. |

The browser tests use deployed metadata, which differs from the repository in configuration. They do not prove that a clean org can reproduce the same result. Persona security, real-model failure handling, concurrency, accessibility and load testing remain unverified. The temporary diagnostic copy is outside this repository.

## Actual UI results

| Step | Observed result |
| --- | --- |
| Open Enrollment App Page | Pass; the deployed app has this navigation item |
| Upload synthetic PDF | Pass |
| AI extraction | Pass; fields, section confidence, warnings and a duplicate candidate appeared |
| Edit identity and confirm | Pass; created `CodexUI Review20260906`, with synthetic `example.com` email |
| Create support plan | Pass; Case **00001027**, status `In Progress` |
| Create onboarding task | Pass; `Complete Patient Onboarding`, due 9 September 2026 |
| Custom support-plan timeline | **Fail:** says “No activity recorded for this plan,” while Open Activities displays the onboarding task |
| Document association | **Fail:** no ContentDocumentLink to either the created patient or plan |
| Coordinator assignment | **Incomplete:** `Primary_Care_Coordinator__c` is null |
| Patient 360 | **Not exposed on the tested patient record:** the standard Person Account page appears; the backend summary test also fails |
| Enrollment provenance | **Incomplete:** `External_Reference_Number__c` is null; enrollment date is today instead of retaining the extracted date |
| Patient activity aggregation | **Fail for the onboarding task:** its `AccountId` and `WhoId` are null; it is linked through `WhatId` to the plan |
| Duplicate DOB display | **Fail:** review input showed March 15, 1985, while the duplicate table displayed March 14; stored DOB is March 15 |
| Return to enrollment | Pass; upload screen is available again |

Test records were retained for inspection:

- [Synthetic patient](https://orgfarm-6c9e8b4c1a-dev-ed.develop.lightning.force.com/lightning/r/Account/001g800000kciC2AAI/view)
- [Support plan 00001027](https://orgfarm-6c9e8b4c1a-dev-ed.develop.lightning.force.com/lightning/r/Case/500g8000027Y2LNAA0/view)
- Onboarding task: `00Tg8000004epeDEAQ`; uploaded file: `Codex_UI_Review_20260906.pdf`.

Screenshots are in `review-artifacts/2026-09-06`: upload, extraction, confirmation, patient record, support plan and status options.

## Prioritized findings

P1 means address before trusting the complete enrollment/support workflow. P2 means address before completing the MVP or expanding usage. Static findings below are distinguished from the browser and deployment observations above.

### 1. P1 — Patient summary fails under the current field permissions

`PatientSummaryController.cls:55` queries affiliation fields, including `Role__c`. `PatientSummaryControllerTest.testGetPatientSummary_Success` fails at this query. FieldDefinition confirms the field exists, but no FieldPermissions grants were returned. None of the four source permission sets grants the affiliation fields. The generic exception wrapper at line 68 hides the useful original message from the Apex test result.

Complete the field-access matrix and test summary loading as each intended persona. Decide which optional sections can degrade gracefully when access is absent. Do not solve this by broadly switching queries to system mode.

**API-version detail:** all source Apex classes use API 67.0. Salesforce now documents user-mode database operations by default for this version. Missing explicit `WITH USER_MODE` is therefore not, by itself, evidence of a CRUD/FLS bypass. The concrete problem here is incomplete grants and untested persona access. [Salesforce Apex security documentation](https://developer.salesforce.com/docs/platform/lwc/guide/apex-security).

### 2. P1 — Changing identity can retain a previously selected patient

In `enrollmentReview.js:85`, editing name or DOB searches again but does not clear `selectedExistingPatientId`. At line 118, confirmation still sends that ID. Reproduction from source: select patient A, change identity to B, then confirm; the server uses A regardless of the changed names. Searches also have no response ordering guard, and failures silently become an empty candidate list at line 156.

Clear selection on identity changes, ignore obsolete responses, display search failure distinctly, and require an explicit final match decision. Add LWC regression tests for these transitions. This was identified statically; no wrong-patient enrollment was performed.

### 3. P1 — Enrollment loses the document and extraction audit trail

`enrollmentReview.html:9` supplies no record ID to the uploader. `AIExtractionService.cls:108` stamps provenance on a transient DTO, but `EnrollmentService.cls:72` never persists it or creates a ContentDocumentLink. The UI test confirmed no file links to the new records.

Link the reviewed file during successful confirmation, retain its version and the review identity/time, and define what happens to rejected or abandoned uploads. Validate file access at confirmation as well as extraction. Salesforce documents that uploads without a record association are private to the authenticated uploader. [File upload documentation](https://developer.salesforce.com/docs/platform/lightning-component-reference/guide/lightning-file-upload.html).

### 4. P1 — The review UI presents information that confirmation discards

HCP and payer fields are editable in `enrollmentReview.html:65` and `:113`, but `EnrollmentService.processEnrollment` saves only the patient, plan and onboarding task. It does not resolve/create HCPs, HCOs or affiliations, preserve payer details, or act on requested services. `PatientSupportPlanService.cls:51` always assigns today's enrollment date, and the extracted external reference is unused.

Define a field-to-record contract. Persist the information required for the supported journey, including the existing date/reference fields. For deliberately deferred payer or service features, make the limits clear in the review flow rather than implying that edits are retained.

### 5. P1 — Human review has incomplete coverage and no verification policy

`isConfirmDisabled` at `enrollmentReview.js:42` checks only last name and program code. The server likewise has no verified-consent or review-attestation check. False signature detections only create warnings; unknown signatures are not added by the mapper's deterministic checks. Address/country and communication preference are written to Account but are not editable in the review screen. Consent, enrollment date, reference and requested services also lack review controls.

Decide the minimum verification policy, including what false/unknown consent means and who can resolve exceptions. Implement it on the server with explicit reviewer confirmation. Add review controls for every extracted field that is written. This is a workflow/control gap, not a legal determination about which consent policy applies.

### 6. P1 — Repeated confirmation creates repeated records

`EnrollmentService.cls:45` creates a patient whenever no existing ID is supplied, and line 73 always creates a new plan. There is no request identity or replay check. `isConfirmDisabled` does not include `isLoading`, and `handleConfirm` has no in-flight guard. A retry after an uncertain response or another browser tab can create duplicates.

Add a persistent idempotency key and define the patient/program re-enrollment policy. Disable confirmation while pending, but retain server-side protection. No duplicate submissions were intentionally sent to the org.

### 7. P2 — The timeline and patient activity queries do not follow the actual data links

`supportPlanTimeline.js:9` accepts arrays but never loads data or accepts a record ID. `Patient_Support_Plan_Record_Page.flexipage-meta.xml:15` embeds it without a supplying parent. The browser reproduced the empty timeline beside a real task.

Separately, `PatientSummaryController.cls:39` filters tasks by AccountId, while `createOnboardingTask` links only WhatId to a Case. The created task's AccountId is null. `AISummaryService.cls:57` and `:67` also omit tasks/events under child support Cases.

Define the activity scope as the selected plan plus its child Cases. Query those relationships, bind the timeline, and test both direct-plan and child-case activity.

### 8. P2 — Coordinator handoff and operational routing are unfinished

`EnrollmentService.cls:77` passes a null coordinator, activates immediately, and assigns onboarding to the current user. The browser confirmed an unassigned plan. `Support_Case_High_Priority_Routing` creates a task on Case creation but has no queue-assignment action and does not run when `SupportCaseService.escalateCase` changes an existing Case to High.

Decide coordinator selection/assignment, ownership, exception handling and whether activation requires assignment. Implement the documented handoff. Define whether escalation updates should create urgent work and prevent duplicate tasks on repeated updates.

### 9. P2 — Case lifecycle and parent invariants are inconsistent

`Support_Process.businessProcess-meta.xml` lists New, Working and Closed. Apex activation/escalation writes In Progress, and the architecture proposes additional statuses. The live CaseStatus inventory lacks In Progress even though Apex successfully wrote it. Treat this as lifecycle inconsistency, not an assertion that the current DML fails.

`SupportCaseService.cls:53` accepts any existing Case as a parent, without validating the PSP record type. Plan activation can reset the start date of an already active/closed plan, and completion/discontinuation lack transition and reason validation. Standard UI/API paths have no metadata rules protecting the key Patient–Program–PSP–child Case relationships.

Choose one lifecycle, deploy its values, validate parent and party types, and enforce transitions consistently across all entry points.

### 10. P2 — Persona permission sets do not implement the promised access model

All four permission sets omit Apex class access and explicit Case object permissions; custom program and affiliation field grants are incomplete. FRM grants Account/Contact create/edit despite the intended limited patient context. Account/Case sharing defaults, manager visibility, queues, role configuration and the promised security test are absent from source.

A user's profile or other permission sets may supply missing access today. That does not make these four sets a reproducible least-privilege model. Record types alone do not establish record visibility. Define baseline profiles and effective grants, implement sharing, then run a two-persona positive/negative access demonstration.

### 11. P2 — UI navigation and context are incomplete

The tested patient opens without the custom Patient 360 component. Its source page needs the correct Person Account/app assignment. Plan detail uses generic Case fields rather than the program/coordinator/support fields needed by coordinators. The enrollment page is configured in the live app but its tab/navigation is missing from source.

`patientSummary.js:61` opens blank Case/Task/Event creation without patient or selected-plan defaults. `careProgramSelector` exists but is not embedded in enrollment, leaving a raw program-code input. It also leaves a spinner after load failure and can search before data is ready. The DOB duplicate column uses a datetime-oriented `date` type, producing the observed one-day shift; use date-only rendering.

Configure and retrieve page assignments/layouts, connect program selection, provide contextual actions and add visible retry/empty states.

### 12. P2 — Org prerequisites and AI settings are not reproducible

The scratch definition lacks Person Accounts and state/country picklist configuration, while `PatientService.cls:50` uses state/country code fields. The prompt requests country without requiring a country code, and the review UI cannot correct that value. The prompt metadata initially contained a placeholder model; during this review it was refreshed to version 2 with `sfdc_ai__DefaultBedrockAnthropicClaude48Opus`. That particular setup gap has been corrected in source, but the prompt design note still says the model is a placeholder. The deployed model worked in the browser test.

The org also has both person-type and business-type RecordTypes named Patient and HCP. Services select record types by developer name alone. The UI test selected the correct person type, but installation must explicitly validate the intended types.

Document prerequisites, retrieve the tested prompt and page configuration, validate record-type identities, normalize addresses deterministically, and prove installation in a clean compatible org.

## Other engineering gaps

- **Tests:** no LWC tests, `System.runAs` persona tests, replay/concurrency tests, or asserted rollback outcomes. Two SupportCaseService routing tests query a record but make no assertions. The bulk test reads five children rather than exercising bulk writes.
- **Transaction contract:** the service comment promises all-or-nothing behavior, but there is no savepoint owned by the service. The UI entry point rethrows failures, allowing transaction rollback; another Apex caller that catches a service exception can retain earlier inserts. Clarify ownership or add explicit rollback and a caught-exception test.
- **Scale:** write services accept single records and perform several queries/DML operations per call. Do not describe them as bulk-safe for batch/import callers without a collection API and realistic volume tests. Several list/subqueries also lack pagination.
- **Affiliations:** no rules prevent self-links, wrong party-type combinations, duplicate active relationships, multiple primary providers or reversed date ranges.
- **Observability:** no durable extraction/review status, correlation ID, operational error record, retry metrics or abandonment handling. Error messages are propagated directly; establish useful diagnostics with deliberate sensitive-data handling.
- **Delivery:** no dependency lockfile, CI pipeline, reproducible seed command, installation validation, rollback/runbook or release acceptance checklist. The only scripts are scaffolding examples.

## Missing plans and architecture decisions

| Area | Decision or deliverable needed |
| --- | --- |
| Domain architecture | Record an ADR for PSP as Case and the unified Affiliation object. The object catalogue still specifies custom `Patient_Support_Plan__c`; the implementation plan and code use Case. |
| Enrollment identity | Matching rules, existing-patient edits, duplicate override reasons, replay keys and allowed re-enrollment |
| Intake lifecycle | Successful/rejected/abandoned states, file retention/linking, recovery after failures, review audit and consent verification |
| HCP/HCO/payer | Which parties V1 must persist and relate; what is explicitly deferred; matching/unknown-party behavior |
| Coordinator and FRM | Assignment rules, shared work visibility, allowed edits, interactions and escalation ownership |
| Reporting | Standard reports/dashboard for active plans, workload, aging, overdue work and enrollment outcomes; absent despite MVP scope |
| AI evaluation | Representative synthetic PDF/image set, field accuracy targets, model/version tracking, malformed/incomplete output, latency and failure criteria |
| Integration | Choose one useful journey and external API, auth, retry/idempotency, monitoring and mocks; implementation is absent |
| Data Cloud | Remains future work. Select dataset, ingestion, mapping and an observable consumer before claiming completion. |
| Delivery | Supported org configuration, setup sequence, persona matrix, clean-org verification, CI gates and demo acceptance criteria |

The existing walkthrough calls the build complete and describes mock extraction, while the working copy calls Prompt Builder. Update README, implementation plan, walkthrough, object catalogue and ADR register together. Separate implemented, verified, partial and deferred items.

## Recommended next steps

1. **Restore a passing baseline.** Fix affiliation FLS/summary behavior, add persona tests, install the declared JS dependencies and create a lockfile. Gate changes on a check-only deployment with all Apex tests plus lint/LWC tests.
2. **Make enrollment trustworthy.** Fix stale patient selection and async search, add replay protection, define/enforce verification, retain the file and reviewed fields, and implement coordinator handoff. Acceptance: one reviewed document produces one correct patient/plan context, with an auditable file link and owner.
3. **Finish ongoing support.** Connect timeline data, include child-case activities, fix DOB rendering, deploy coherent statuses and contextual actions, and activate the correct Patient 360/layouts. Acceptance: onboarding and urgent support work are visible from the patient and selected plan, and cases can complete through the UI.
4. **Complete the stated MVP.** Add HCP/HCO relationships required by enrollment, the FRM scenario and standard manager reporting. Record scope decisions for payer/consent depth instead of leaving editable-but-discarded fields.
5. **Prove delivery, then expand.** Synchronize tested org configuration to source, validate a clean installation and documented persona journeys, then implement the selected integration. Keep Data Cloud and further AI features behind explicit acceptance criteria.

The existing service separation, native Case/Task model, human confirmation step and improved extraction mapper are useful foundations. The immediate work is completing the contracts between them and demonstrating those contracts under the intended user permissions.

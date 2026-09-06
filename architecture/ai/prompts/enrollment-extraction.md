# Prompt Template: Enrollment Document Extraction

|                |                                                                                                        |
| -------------- | ------------------------------------------------------------------------------------------------------ |
| Template       | `Enrollment_Document_Extraction` (Flex, Prompt Builder)                                                 |
| Metadata       | `force-app/main/default/genAiPromptTemplates/Enrollment_Document_Extraction.genAiPromptTemplate-meta.xml` |
| Version        | 1.0                                                                                                     |
| Model          | Anthropic Claude Opus 4.8 on Amazon Bedrock, selected in Prompt Builder                                  |
| Invoked by     | `AIExtractionService` via `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate`                     |
| Reference form | [`sample-enrollment-form.pdf`](sample-enrollment-form.pdf)                                              |

The prompt text itself lives in the template metadata; this file is the design record and the
review trail. **Change both together, and bump the version.**

Per `architecture/ai/README.md`, the pipeline is:

```
File (ContentDocument)
  -> Flex prompt template, File input, multimodal model, Einstein Trust Layer
  -> JSON -> EnrollmentExtractionResult
  -> Review UI -> human confirmation -> Salesforce records
```

The model never writes to Salesforce. It returns a DTO an enrollment specialist edits and
confirms; only `EnrollmentService.processEnrollment` creates records.

---

## Why Prompt Builder rather than a direct callout

The model reads the file itself. Passing the `ContentDocument` id as a File input means no Apex
code ever loads, base64-encodes or transmits the document, which removes the whole class of
problems that route carries: the 6 MB synchronous Apex heap ceiling (a file is otherwise held as
a Blob, again as a base64 String, and again inside the request body), a named credential and API
key to rotate, and a hand-rolled retry and error-mapping layer. It also puts the call inside the
Einstein Trust Layer, so PII masking, toxicity screening, zero-retention and audit logging apply
without extra work, and the model can be changed by an admin in Prompt Builder rather than by a
deployment.

What it costs: there is no `output_config.format` equivalent, so JSON validity is asked for in
the prompt rather than enforced by the API. `EnrollmentExtractionMapper` therefore assumes
nothing — it recovers the JSON from code fences or surrounding prose, treats every field as
possibly absent, and turns a value it cannot read into a warning instead of an exception.

---

## Inputs

| Input                | Type                       | Value                                                             |
| -------------------- | -------------------------- | ----------------------------------------------------------------- |
| `enrollmentDocument`  | File (`ContentDocument`)   | The uploaded form. Passed as `{'id' => contentDocumentId}`         |
| `programCatalog`      | Free text                  | One line per active `Care_Program__c`: code, name, therapy area, product |
| `receivedDate`        | Free text                  | Today's date, for context when the form states no date             |

`programCatalog` is the one that earns its place. Without it the model returns a plausible
program code read off the form, `EnrollmentService.getProgramByCode` finds nothing, and the
specialist sees "Care Program not found with code: ..." with no explanation. Grounding the code
in this org's own active programs turns a free-text guess into a constrained choice.

Apex builds these with `PromptTemplateService.recordValue()` / `.textValue()` and keys them
`Input:<apiName>`. A File input takes the **ContentDocument** id, not the ContentVersion id —
`EnrollmentDocument.validate()` resolves whichever the caller holds.

---

## Output contract

The prompt asks for a single JSON object, mapped field-for-field by
`EnrollmentExtractionMapper`:

```json
{
  "documentType": "...",
  "externalReferenceNumber": "ENR-2026-00417",
  "patient":    { "firstName": …, "lastName": …, "dateOfBirth": "yyyy-mm-dd", "phone": …, "email": …,
                  "street": …, "city": …, "state": …, "postalCode": …, "country": …,
                  "preferredLanguage": …, "communicationPreference": …, "confidence": 0.0 },
  "hcp":        { "firstName": …, "lastName": …, "npi": …, "specialty": …, "confidence": 0.0 },
  "hco":        { "name": …, "siteType": …, "taxId": …, "confidence": 0.0 },
  "program":    { "programCode": …, "programName": …, "therapyArea": …, "productName": …, "confidence": 0.0 },
  "payer":      { "payerName": …, "memberId": …, "groupNumber": …, "confidence": 0.0 },
  "enrollment": { "enrollmentSource": …, "enrollmentDate": …, "servicesRequested": [...],
                  "patientConsentSigned": …, "prescriberSignaturePresent": …, "confidence": 0.0 },
  "warnings": ["..."]
}
```

Controlled fields are constrained to this org's picklist values (`preferredLanguage`,
`communicationPreference`, `specialty`, `siteType`, `enrollmentSource`); anything that does not
map becomes `null` plus a warning rather than a stretched match.

---

## Setup

### Metadata shape at API 67.0

Established by deploy validation against a real org, because the published examples disagree:

| Element                                | At 67.0                                                                                   |
| -------------------------------------- | ------------------------------------------------------------------------------------------ |
| `activeVersionIdentifier` (root)        | Required. `activeVersion` is **rejected**                                                  |
| `versionIdentifier` (in templateVersions) | Required. `versionNumber` is **rejected**                                                 |
| `createdInVersion`                      | **Rejected.** Present in older published examples; must be omitted                          |
| Both identifier values                  | Must be hash-form, `<base64>_<n>`. A plain `1` fails with "version identifier is 1 invalid" |

The identifier here is the SHA-256 of the `<content>` element, base64-encoded, suffixed `_1`. It
satisfies the format check and is reproducible, but it is not the value the platform itself
generates — after the first save in Prompt Builder, retrieve the template and let the org's own
identifier win.

### Model selection

`primaryModel` is still the placeholder `REPLACE_WITH_ORG_MODEL_API_NAME`. Deploy validation does
**not** check this value, so it deploys cleanly and then runs on whatever the default is — set it
deliberately. The org exposes no API that enumerates the available models (`ExternalAIModel` is
empty unless you have registered a BYOM model), so the list in Prompt Builder is the only source:

1. Deploy, then open the template in Prompt Builder.
2. Pick the Bedrock Claude Opus 4.8 entry from the model list, and confirm under
   **Model Limitations** that it accepts PDF and image inputs.
3. Save and activate, then retrieve so the repo holds the real model name and identifiers:

```bash
sf project retrieve start -m "GenAiPromptTemplate:Enrollment_Document_Extraction"
```

Users also need Einstein Generative AI enabled and access to the template.

---

## Review log

Per the AI Coding Requirement in `architecture/ai/README.md`, this is the
prompt -> artifact -> review -> correction trail for v1.0.

| #   | Issue found in review                                                                                                                                                         | Correction                                                                                                                             |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | The first build called the Anthropic Messages API directly from Apex: base64 encoding, a named credential, an API key, retry and error mapping — several hundred lines of it.   | Replaced with a Flex prompt template and a File input. Prompt Builder reads the document, and the Trust Layer handles auth and masking.   |
| 2   | The model was free to return any `programCode` it read off the form, which fails `getProgramByCode` for codes that are read correctly but do not exist in this org.             | Added the `programCatalog` input and constrained the model to the org's active programs, or null.                                          |
| 3   | The draft asked for one overall confidence, which tells a reviewer nothing about _where_ to look.                                                                               | Per-section confidence, mapped onto the four badges the review LWC already renders. `overallConfidence` is the weakest section, not the average. |
| 4   | Confidence scores clustered near 0.95, because the prompt never said what the numbers meant.                                                                                    | Added four calibration bands and an instruction not to inflate scores.                                                                    |
| 5   | Nothing stopped a hostile enrollment form from carrying instructions in its own text.                                                                                           | Added the data-not-instructions line, plus a scope paragraph refusing clinical interpretation even when a later instruction asks for it.   |
| 6   | Checked against the reference form: the address is printed as one line (`742 Evergreen Terrace, Springfield, IL 62704`), but the prompt asked for `street`/`city`/`state` with no instruction to split it. | Added an address-splitting normalisation rule, with null plus a warning where the boundaries are unclear.                                 |
| 7   | Checked against the reference form: the intake number `ENR-2026-00417`, the stated received date, and the ticked services list were all being dropped, though `Case.External_Reference_Number__c` and `Case.Enrollment_Date__c` already exist. | Added `externalReferenceNumber`, `enrollment.enrollmentDate` and `enrollment.servicesRequested` to the output contract and the DTO.       |
| 8   | The reference form's checkbox groups (`✓Phone  Email  Text / SMS  Mail`) needed explicit handling, and `Text / SMS` has no equivalent in the `Communication_Preference__c` picklist. | Added a checkbox-reading rule, and kept the standing instruction to return null and warn rather than stretch a mapping.                    |
| 9   | The file-upload LWC accepted `.tiff`, `.doc` and `.docx`, none of which the models read.                                                                                        | Narrowed the picker to PDF/PNG/JPEG, and `EnrollmentDocument` rejects the rest with an instruction ("Fax servers usually offer a PDF copy"). |
| 10  | `AIExtractionService` originally fell back to `AIExtractionMock` whenever the model was unavailable.                                                                            | Removed. Handing a specialist synthetic patient details to review and confirm is worse than an error message. The mock is now test and demo only. |

## Known limits

- **Latency.** A multi-page scan takes tens of seconds. The call is synchronous behind the LWC
  spinner. If forms get longer, move it to a Queueable with a Platform Event back to the UI.
- **JSON validity is asked for, not enforced.** See the note under "Why Prompt Builder" above;
  the mapper is written on that assumption and `EnrollmentExtractionMapperTest` covers the messy
  shapes.
- **`servicesRequested` is captured but not acted on.** Creating the matching child Cases
  (Benefits Verification, Prior Authorization, ...) is the obvious next step.

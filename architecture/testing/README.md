# Testing

Apex tests cover positive, negative, bulk, missing-data, security where
applicable, callout mocks and outcome assertions.

LWC tests should cover meaningful behavior where feasible: extraction
rendering, edits, validation and server errors.

End-to-end scenarios: 1. Enrollment: document -\> extraction -\> review
-\> Patient -\> Support Plan -\> onboarding Task. 2. Ongoing Support:
plan -\> Case -\> Event/Task -\> resolution. 3. FRM: access Case -\>
stakeholder interaction -\> outcome -\> coordinator visibility. 4.
Security: personas have different access. 5. AI failure:
incorrect/incomplete extraction is corrected before confirmation.

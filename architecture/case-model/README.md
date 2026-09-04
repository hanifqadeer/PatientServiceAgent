# Support Case Model

Use standard `Case` as the service execution record and associate it
with Patient Support Plan.

Why: ownership, queues, status, priority, assignment, escalation,
activities, reporting and extensibility already exist.

Candidate categories: - Access & Reimbursement: Benefits Verification,
Prior Authorization, Appeals, Reimbursement. - Patient Support:
Education, Program Question, General Assistance. - Coordination:
Appointment/Coordination, Site of Care, Provider Coordination.

Candidate lifecycle:
`New -> In Progress -> Waiting on External Party -> Resolved -> Closed`.

Do not create one custom object per service category unless its
data/lifecycle genuinely diverges.

Future ADR: if one Case requires many HCP/HCO/Payer/Site participants,
evaluate a Case Stakeholder relationship instead of many direct lookups.

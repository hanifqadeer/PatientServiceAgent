# Apex + LWC Patterns

Conceptual structure where justified:

``` text
LWC -> Apex Controller -> Service -> Selector/Data Access -> Salesforce
```

Not every feature needs every layer.

Enrollment example:
`EnrollmentReview LWC -> EnrollmentController -> EnrollmentService -> Patient/Program selectors`.

LWC owns presentation/user state. Controller is a UI-facing boundary.
Service owns reusable business operations. Selector centralizes
complex/reused query logic when useful.

Standards: bulk-safe, no SOQL/DML in loops, intentional sharing,
CRUD/FLS strategy, meaningful errors, testability and clear transaction
ownership.

Learner topics: wire vs imperative, LDS/UI API vs Apex, component
communication, governor limits, sharing/security and why each class
exists.

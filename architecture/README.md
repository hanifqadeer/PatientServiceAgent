# Main Architecture

The application absorbs enterprise complexity internally while exposing
simple role-based workflows.

``` text
User Experience
      |
Standard Salesforce UI / Targeted LWC
      |
Controller / Automation Boundary
      |
Reusable Service / Domain Logic
      |
Selectors / Data Access where justified
      |
Salesforce Data Model
      |
AI / Data Cloud / Integrations
```

## Decision Sequence

1.  Understand the business requirement.
2.  Evaluate standard Salesforce capability.
3.  Evaluate configuration.
4.  Evaluate Flow.
5.  Use Apex for justified complex/reusable transactional logic.
6.  Use custom LWC when standard UX does not satisfy the workflow.
7.  Use custom objects when a business entity/relationship genuinely has
    its own data or lifecycle.

This is **standard-first, not standard-only**.

See child folders for personas, journeys, model, security, AI,
automation, code patterns, ADRs and build instructions.

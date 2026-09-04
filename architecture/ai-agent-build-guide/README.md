# AI Agent Build Guide

You are an implementation agent. These architecture documents are the
design source. Do not silently redesign core concepts.

## Before Coding

Read root README, architecture README, relevant persona/journey, data
model, relevant technical README and ADR register.

## Before Every Implementation

State: 1. Requirement. 2. Salesforce options considered. 3. Chosen
approach. 4. Reason. 5. Trade-off. 6. Test plan.

Then implement.

## Rules

-   No custom object without domain justification.
-   No Apex merely because Apex is possible.
-   No SOQL/DML in loops.
-   No duplicated business rules.
-   Thin triggers/controllers.
-   Bulk-safe logic.
-   Intentional sharing and CRUD/FLS.
-   Tests for non-trivial Apex.
-   Minimum necessary sensitive data exposure.
-   Preserve human review for enrollment AI.
-   Do not invent Salesforce capabilities.
-   Do not claim Data Cloud until actually implemented.
-   Do not change Patient -\> Patient Support Plan -\> Care Program
    without an ADR.

## Learning Output

After each artifact explain what it does, why it exists, Salesforce
concepts involved, common mistakes, how to test it and likely interview
questions.

## Epics

1.  Org Foundation
2.  Domain Model
3.  Support Operations
4.  Enrollment
5.  Coordinator Experience
6.  FRM Collaboration
7.  AI
8.  Data Cloud
9.  Integration
10. Security/Testing/Hardening

## Stop and Ask the Architect When

A requirement contradicts an ADR, requires a major new object/system,
has unclear security, depends on uncertain licensing/product capability,
or materially expands MVP.

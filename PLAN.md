# AI-Powered Pharma Patient Services Hub

This repository is the master architecture guide for a Salesforce-based
pharmaceutical Patient Services product.

## Product Vision

Create a simple user experience on top of a reusable enterprise
Salesforce foundation. The product supports intelligent patient
enrollment, Care Programs, Patient Support Plans, Support Cases, HCP/HCO
relationships, operational activities, AI assistance, and future Data
Cloud expansion.

## Core Principle

**Simple Experience, Enterprise Foundation.**

Enterprise does not mean maximum complexity. Every standard/custom
object, Flow, Apex class, LWC, integration, AI capability, and
relationship must have a defensible business or engineering reason.

## Core Model

``` text
Patient (Person Account)
        |
        | 1:M
        v
Patient Support Plan -------- M:1 -------- Care Program
        |
        +---- Support Cases (Case)
        +---- Tasks
        +---- Events
        +---- Files
        +---- AI Summary / Insights

Patient <---- Patient-HCP Relationship ----> HCP (Person Account)
HCP <--------- HCP-HCO Affiliation ---------> HCO (Business Account)
```

**Care Program** is the company's program definition.\
**Patient Support Plan** is the patient-specific participation and
operational support context.\
A separate Care Program Enrollment object is intentionally not part of
V1 because the Support Plan already contains the participation
lifecycle.

## Repository Structure

``` text
architecture/
  README.md
  principles/README.md
  personas/
    README.md
    enrollment-specialist/README.md
    care-coordinator/README.md
    care-coordinator-manager/README.md
    field-reimbursement-manager/README.md
  journeys/
    README.md
    enrollment/README.md
    ongoing-support/README.md
  data-model/
    README.md
    objects/README.md
    relationships/README.md
  case-model/README.md
  ai/README.md
  data-cloud/README.md
  automation/README.md
  apex-lwc/README.md
  security/README.md
  integrations/README.md
  ux/README.md
  decisions/README.md
  testing/README.md
  roadmap/README.md
  ai-agent-build-guide/README.md
```

## Build Order

1.  Org foundation and Person Accounts.
2.  Party/domain model.
3.  Care Program + Patient Support Plan.
4.  Case/Task/Event/Files.
5.  Security.
6.  Enrollment workflow.
7.  Coordinator experience.
8.  FRM collaboration.
9.  AI.
10. One meaningful integration.
11. Data Cloud with a real external dataset.
12. Tests, ADRs, demo and interview preparation.

## AI-Agent Rule

Read the relevant architecture documents before coding. Do not silently
redesign the domain. For each task explain requirement, options, choice,
reason, trade-off, implementation and tests. The learner must understand
every generated artifact.

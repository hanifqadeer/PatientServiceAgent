# Architecture Decision Register

  ----------------------------------------------------------------------------------------
  ID             Decision        Choice           Reason                  Revisit
  -------------- --------------- ---------------- ----------------------- ----------------
  ADR-001        Patient         Person Account   Individual patient      Org/domain
                                                  party model             capability
                                                                          changes

  ADR-002        HCP             Person Account   Individual              Domain/package
                                                  professional +          needs differ
                                                  affiliations            

  ADR-003        HCO             Business Account Organization maps       Specialized
                                                  naturally to Account    lifecycle
                                                                          emerges

  ADR-004        Program         Patient Support  Avoid duplicate         Enrollment
                 participation   Plan links       enrollment lifecycle    becomes
                                 Patient + Care                           independent
                                 Program                                  

  ADR-005        Support request Case             Native service          Case no longer
                                                  foundation              fits
                                                                          lifecycle/data

  ADR-006        Scheduled       Event            Native activity         Specialized
                 interaction                      model/future            appointment
                                                  integration path        lifecycle

  ADR-007        Work            Task             Native actionable work  Specialized work
                                                                          entity required

  ADR-008        HCP-HCO         Affiliation      True many-to-many       Standard
                                 relationship                             capability fully
                                                                          fits

  ADR-009        Patient-HCP     Relationship     Avoid single-HCP        Requirement
                                 model            assumption              proves otherwise

  ADR-010        AI enrollment   Human-reviewed   Accuracy/governance     Approved
                                 extraction                               low-risk
                                                                          automation

  ADR-011        UI              Standard +       Avoid unnecessary       Standard UX
                                 targeted LWC     custom UI               fails
                                                                          requirement

  ADR-012        Logic           Reusable         Maintainability/reuse   Logic remains
                                 services where                           trivial
                                 justified                                
  ----------------------------------------------------------------------------------------

## ADR Template

**Context** --- problem.\
**Options** --- realistic alternatives.\
**Decision** --- chosen approach.\
**Why** --- current/future fit.\
**Trade-offs** --- accepted cost/complexity.\
**Revisit Trigger** --- condition that changes the decision.

Never answer "because it is best practice" without explaining the
problem the practice solves.

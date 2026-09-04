# Relationship Design

-   Patient -\> Patient Support Plan: 1:M.
-   Care Program -\> Patient Support Plan: 1:M.
-   Patient Support Plan -\> Support Case: 1:M.
-   Patient \<-\> HCP: many-to-many relationship model.
-   HCP \<-\> HCO: many-to-many affiliation model.

Before creating custom junctions, evaluate standard Salesforce
relationship capabilities available in the target org. Use custom
relationships when domain-specific attributes, lifecycle, history,
reporting or behavior justify them.

A junction is not used because it "looks enterprise"; it is used because
the relationship itself has business meaning.

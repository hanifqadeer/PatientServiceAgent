# Data Model

``` text
Patient (Person Account)
   |
   +----< Patient Support Plan >---- Care Program
                    |
                    +----< Case

Patient >----< Patient-HCP Relationship >----< HCP (Person Account)
HCP >----< HCP-HCO Affiliation >----< HCO (Business Account)
```

Tasks, Events and Files support the appropriate operational context.

## Why No Separate Care Program Enrollment in V1?

Patient Support Plan already represents the Patient's participation in
the Care Program and contains status, dates, coordinator and
patient-specific support context.

Revisit if enrollment becomes an independent lifecycle that must exist
before a Support Plan, supports multiple applications, requires separate
auditing, or otherwise becomes materially distinct.

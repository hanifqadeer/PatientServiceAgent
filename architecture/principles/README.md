# Architecture Principles

1.  **Simple Experience, Enterprise Foundation** --- complexity belongs
    behind the workflow.
2.  **Business Requirement Before Technology** --- never begin with "we
    need Apex/LWC."
3.  **Standard First** --- prefer native capability when it represents
    the requirement correctly.
4.  **Custom When Justified** --- domain correctness, reuse,
    maintainability, security or scale can justify customization.
5.  **Relationships Are Data** --- meaningful many-to-many relationships
    deserve proper modelling.
6.  **Reusable Business Logic** --- avoid duplicating rules across UI,
    Flow and Apex.
7.  **Thin Entry Points** --- triggers/controllers delegate reusable
    logic.
8.  **Bulk/Transaction Aware** --- design for Salesforce limits and
    transactional behavior.
9.  **Secure by Design** --- sharing, CRUD/FLS and least privilege are
    architecture inputs.
10. **Human-in-the-Loop AI** --- AI assists; important extracted data is
    reviewed.
11. **Build for Foreseeable Change** --- accept upfront cost only when
    future value is credible.
12. **Avoid Speculative Architecture** --- do not build abstractions for
    imaginary requirements.

For every decision Hanif must answer: What problem? What alternatives?
Why this? What trade-off? When would we change it?

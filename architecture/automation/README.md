# Automation

Use Flow for straightforward maintainable declarative automation. Use
Apex for complex/reusable transactional logic, advanced collection
processing, integrations or cases where Flow becomes difficult to
maintain/test.

Potential Flow: high-priority Support Case routing/escalation.

Potential plan activation automation: coordinator
assignment/confirmation and onboarding Task.

Never duplicate the same business rule independently across Flow,
trigger, LWC and Apex.

If triggers are needed: `Trigger -> Handler -> Service/Domain`.

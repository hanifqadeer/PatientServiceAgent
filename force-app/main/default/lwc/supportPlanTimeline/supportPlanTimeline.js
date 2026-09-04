import { LightningElement, api, track } from 'lwc';

/**
 * @description Timeline view of Cases, Tasks, and Events under a Support Plan.
 *              Displays activity in chronological order with status color coding.
 *              Accepts data from parent component via @api properties.
 */
export default class SupportPlanTimeline extends LightningElement {
    @api cases = [];
    @api tasks = [];
    @api events = [];

    isLoading = false;

    get timelineItems() {
        const items = [];

        // Cases
        if (this.cases) {
            this.cases.forEach((c) => {
                items.push({
                    id: c.Id,
                    type: 'Case',
                    subject: c.Subject || c.CaseNumber,
                    status: c.Status,
                    dateValue: new Date(c.CreatedDate),
                    dateDisplay: this._formatDate(c.CreatedDate),
                    detail: c.Support_Category__c || '',
                    iconName: 'standard:case',
                    iconContainerClass: 'slds-icon_container slds-icon-standard-case',
                    statusCss: this._statusCss(c.Status)
                });
            });
        }

        // Tasks
        if (this.tasks) {
            this.tasks.forEach((t) => {
                items.push({
                    id: t.Id,
                    type: 'Task',
                    subject: t.Subject,
                    status: t.Status,
                    dateValue: t.ActivityDate ? new Date(t.ActivityDate) : new Date(),
                    dateDisplay: this._formatDate(t.ActivityDate),
                    detail: t.Priority ? 'Priority: ' + t.Priority : '',
                    iconName: 'standard:task',
                    iconContainerClass: 'slds-icon_container slds-icon-standard-task',
                    statusCss: this._statusCss(t.Status)
                });
            });
        }

        // Events
        if (this.events) {
            this.events.forEach((e) => {
                items.push({
                    id: e.Id,
                    type: 'Event',
                    subject: e.Subject,
                    status: 'Scheduled',
                    dateValue: new Date(e.StartDateTime),
                    dateDisplay: this._formatDate(e.StartDateTime),
                    detail: e.Location || '',
                    iconName: 'standard:event',
                    iconContainerClass: 'slds-icon_container slds-icon-standard-event',
                    statusCss: ''
                });
            });
        }

        // Sort by date descending (most recent first)
        items.sort((a, b) => b.dateValue - a.dateValue);
        return items;
    }

    _formatDate(dateStr) {
        if (!dateStr) return '';
        const d = new Date(dateStr);
        return d.toLocaleDateString('en-US', {
            year: 'numeric', month: 'short', day: 'numeric'
        });
    }

    _statusCss(status) {
        if (!status) return '';
        const lower = status.toLowerCase();
        if (lower === 'closed' || lower === 'completed') return 'status-closed';
        if (lower === 'in progress') return 'status-in-progress';
        if (lower === 'new' || lower === 'not started') return 'status-new';
        return '';
    }
}

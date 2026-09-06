import { LightningElement, api } from 'lwc';

/**
 * @description Shown while a prompt template reads an uploaded enrollment form.
 *
 *              Extraction on a scanned form runs for tens of seconds, which is long enough that
 *              a bare spinner reads as a hang. The step captions below are honest about the
 *              order the work happens in, but they are paced on a timer rather than driven by
 *              real progress — the Apex call is a single round trip with nothing to report
 *              until it returns.
 */
const STEP_MESSAGES = [
    'Opening the document…',
    'Reading patient details…',
    'Looking up the prescriber…',
    'Matching the care program…',
    'Checking payer information…',
    'Scoring confidence per section…',
    'Almost there — tidying up the results…'
];

/** Long enough to read, short enough that the caption never looks stuck. */
const STEP_INTERVAL_MS = 2600;

export default class AiReadingIndicator extends LightningElement {
    /** Name of the file being read. Shown under the status line when supplied. */
    @api fileName;

    currentStep = STEP_MESSAGES[0];

    _stepIndex = 0;
    _timer;

    connectedCallback() {
        this._timer = setInterval(() => {
            // Hold on the last caption rather than looping back to "Opening the document",
            // which would suggest the work restarted.
            if (this._stepIndex < STEP_MESSAGES.length - 1) {
                this._stepIndex += 1;
                this.currentStep = STEP_MESSAGES[this._stepIndex];
            }
        }, STEP_INTERVAL_MS);
    }

    disconnectedCallback() {
        if (this._timer) {
            clearInterval(this._timer);
            this._timer = undefined;
        }
    }
}

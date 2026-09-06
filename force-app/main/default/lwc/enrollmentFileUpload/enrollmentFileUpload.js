import { LightningElement, api } from 'lwc';

/**
 * @description File upload component for enrollment documents.
 *              Fires a custom event with uploaded file IDs when upload completes.
 *              Used within the Enrollment Review flow.
 */
export default class EnrollmentFileUpload extends LightningElement {
    @api recordId;

    uploadedFiles;

    // Only what the multimodal prompt template can actually read. Offering .tiff, .doc or
    // .docx here just moves the rejection from the file picker to the extraction step.
    get acceptedFormats() {
        return ['.pdf', '.png', '.jpg', '.jpeg'];
    }

    handleUploadFinished(event) {
        this.uploadedFiles = event.detail.files;
        const documentId = this.uploadedFiles[0]?.documentId;
        this.dispatchEvent(
            new CustomEvent('fileupload', {
                detail: { documentId, files: this.uploadedFiles }
            })
        );
    }
}

import { LightningElement, api } from 'lwc';

/**
 * @description File upload component for enrollment documents.
 *              Fires a custom event with uploaded file IDs when upload completes.
 *              Used within the Enrollment Review flow.
 */
export default class EnrollmentFileUpload extends LightningElement {
    @api recordId;

    uploadedFiles;

    get acceptedFormats() {
        return ['.pdf', '.png', '.jpg', '.jpeg', '.tiff', '.doc', '.docx'];
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

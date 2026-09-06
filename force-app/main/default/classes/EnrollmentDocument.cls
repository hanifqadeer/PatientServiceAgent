/**
 * @description Pre-flight check on an uploaded enrollment document before it is handed to a
 *              prompt template, and resolution of whichever file id the caller happens to hold
 *              down to the ContentDocument id that a File input expects.
 *
 *              The template would fail on an unsupported file anyway, but it fails with a
 *              platform error. Checking here means an enrollment specialist who uploads a Word
 *              document is told to save it as a PDF instead of being shown a stack trace.
 */
public with sharing class EnrollmentDocument {
    /** File types the multimodal models accept. */
    private static final Set<String> SUPPORTED_EXTENSIONS = new Set<String>{
        'pdf', 'png', 'jpg', 'jpeg'
    };

    /**
     * Formats a coordinator is likely to upload that the models cannot read.
     * Naming them turns a shrug into an instruction.
     */
    private static final Map<String, String> UNSUPPORTED_HINTS = new Map<String, String>{
        'tif' => 'TIFF is not supported. Fax servers usually offer a PDF copy — upload that instead.',
        'tiff' => 'TIFF is not supported. Fax servers usually offer a PDF copy — upload that instead.',
        'doc' => 'Word documents are not supported. Save or print the form as a PDF and upload that.',
        'docx' => 'Word documents are not supported. Save or print the form as a PDF and upload that.',
        'heic' => 'HEIC photos are not supported. Export the image as JPEG or PNG.',
        'bmp' => 'BMP images are not supported. Export the image as PNG or JPEG.',
        'gif' => 'GIF images are not supported for enrollment forms. Upload a PDF, PNG or JPEG.'
    };

    /**
     * Model file size limit as surfaced in Prompt Builder. Checked here so an oversized scan
     * is rejected with a readable message rather than a generic template failure.
     */
    private static final Integer MAX_FILE_BYTES = 10 * 1024 * 1024;

    public Id contentDocumentId;
    public Id contentVersionId;
    public String fileName;
    public String fileExtension;
    public Integer sizeBytes;

    private EnrollmentDocument() {
    }

    /**
     * @description Resolve and validate an uploaded file.
     * @param fileId A ContentDocumentId (069) or ContentVersionId (068). The file-upload LWC
     *               hands back the document id; other callers may hold a version id.
     * @return The validated document, carrying the ContentDocument id to pass to the template.
     * @throws EnrollmentDocumentException when the file is missing, empty, oversized, or in a
     *         format the model cannot read.
     */
    public static EnrollmentDocument validate(Id fileId) {
        if (fileId == null) {
            throw new EnrollmentDocumentException('No document was supplied.');
        }

        ContentVersion version = queryLatestVersion(fileId);
        String extension = normalizeExtension(version);

        if (!SUPPORTED_EXTENSIONS.contains(extension)) {
            String guidance = UNSUPPORTED_HINTS.get(extension);
            throw new EnrollmentDocumentException(
                String.isNotBlank(guidance)
                    ? guidance
                    : 'Files of type "' + extension + '" cannot be read by AI extraction. ' +
                      'Supported formats: PDF, PNG and JPEG.'
            );
        }
        if (version.ContentSize == null || version.ContentSize == 0) {
            throw new EnrollmentDocumentException(
                '"' + version.Title + '" is empty. Upload the document again.'
            );
        }
        if (version.ContentSize > MAX_FILE_BYTES) {
            throw new EnrollmentDocumentException(
                '"' + version.Title + '" is ' + formatMb(version.ContentSize) + ', over the ' +
                formatMb(MAX_FILE_BYTES) + ' limit. Split the document or reduce the scan resolution.'
            );
        }

        EnrollmentDocument document = new EnrollmentDocument();
        document.contentDocumentId = version.ContentDocumentId;
        document.contentVersionId = version.Id;
        document.fileName = String.isNotBlank(version.PathOnClient) ? version.PathOnClient : version.Title;
        document.fileExtension = extension;
        document.sizeBytes = version.ContentSize;
        return document;
    }

    private static ContentVersion queryLatestVersion(Id fileId) {
        String objectName = String.valueOf(fileId.getSobjectType());
        List<ContentVersion> versions;

        if (objectName == 'ContentDocument') {
            versions = [
                SELECT Id, ContentDocumentId, Title, PathOnClient, FileExtension, FileType, ContentSize
                FROM ContentVersion
                WHERE ContentDocumentId = :fileId AND IsLatest = TRUE
                LIMIT 1
            ];
        } else if (objectName == 'ContentVersion') {
            versions = [
                SELECT Id, ContentDocumentId, Title, PathOnClient, FileExtension, FileType, ContentSize
                FROM ContentVersion
                WHERE Id = :fileId
                LIMIT 1
            ];
        } else {
            throw new EnrollmentDocumentException(
                'Expected a file id (ContentDocument or ContentVersion) but received a ' + objectName + '.'
            );
        }

        if (versions.isEmpty()) {
            throw new EnrollmentDocumentException(
                'The uploaded file could not be found, or you do not have access to it.'
            );
        }
        return versions[0];
    }

    private static String normalizeExtension(ContentVersion version) {
        String extension = String.isNotBlank(version.FileExtension)
            ? version.FileExtension
            : version.FileType;
        return String.isBlank(extension) ? '' : extension.trim().toLowerCase();
    }

    private static String formatMb(Integer bytes) {
        return Decimal.valueOf(bytes).divide(1048576, 1) + ' MB';
    }

    public class EnrollmentDocumentException extends Exception {}
}

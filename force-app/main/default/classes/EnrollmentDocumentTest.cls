/**
 * @description Tests for EnrollmentDocument: id resolution and the pre-flight checks that
 *              turn a platform failure into an instruction the specialist can act on.
 */
@IsTest
private class EnrollmentDocumentTest {
    private static ContentVersion createFile(String pathOnClient, String body) {
        ContentVersion version = new ContentVersion(
            Title = 'Enrollment Form',
            PathOnClient = pathOnClient,
            VersionData = Blob.valueOf(body),
            IsMajorVersion = true
        );
        insert version;
        return [
            SELECT Id, ContentDocumentId, ContentSize, FileExtension
            FROM ContentVersion
            WHERE Id = :version.Id
        ];
    }

    @IsTest
    static void acceptsAPdfAndReturnsTheContentDocumentId() {
        ContentVersion version = createFile('enrollment-form.pdf', '%PDF-1.4 sample');

        Test.startTest();
        EnrollmentDocument document = EnrollmentDocument.validate(version.ContentDocumentId);
        Test.stopTest();

        System.assertEquals(version.ContentDocumentId, document.contentDocumentId, 'Document id should resolve.');
        System.assertEquals('pdf', document.fileExtension, 'Extension should normalise to lower case.');
        System.assertEquals('enrollment-form.pdf', document.fileName, 'File name should come from PathOnClient.');
        System.assert(document.sizeBytes > 0, 'Size should be populated.');
    }

    @IsTest
    static void resolvesAContentVersionIdDownToItsDocument() {
        ContentVersion version = createFile('scan.png', 'fake png bytes');

        Test.startTest();
        EnrollmentDocument document = EnrollmentDocument.validate(version.Id);
        Test.stopTest();

        System.assertEquals(
            version.ContentDocumentId,
            document.contentDocumentId,
            'A version id should still yield the document id the File input needs.'
        );
    }

    @IsTest
    static void acceptsJpegScans() {
        ContentVersion version = createFile('fax-page.jpeg', 'fake jpeg bytes');

        Test.startTest();
        EnrollmentDocument document = EnrollmentDocument.validate(version.ContentDocumentId);
        Test.stopTest();

        System.assertEquals('jpeg', document.fileExtension, 'JPEG scans are a normal fax output.');
    }

    @IsTest
    static void rejectsTiffWithAFaxSpecificHint() {
        ContentVersion version = createFile('inbound-fax.tiff', 'fake tiff bytes');

        Test.startTest();
        try {
            EnrollmentDocument.validate(version.ContentDocumentId);
            System.assert(false, 'TIFF should be rejected.');
        } catch (EnrollmentDocument.EnrollmentDocumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('PDF copy'),
                'A fax user should be told where to find the PDF. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void rejectsWordDocumentsWithAnInstruction() {
        ContentVersion version = createFile('form.docx', 'fake docx bytes');

        Test.startTest();
        try {
            EnrollmentDocument.validate(version.ContentDocumentId);
            System.assert(false, 'Word documents should be rejected.');
        } catch (EnrollmentDocument.EnrollmentDocumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('save or print the form as a PDF'),
                'The message should say what to do instead. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void rejectsAnUnknownExtensionAndListsWhatIsSupported() {
        ContentVersion version = createFile('notes.zip', 'fake zip bytes');

        Test.startTest();
        try {
            EnrollmentDocument.validate(version.ContentDocumentId);
            System.assert(false, 'An unknown type should be rejected.');
        } catch (EnrollmentDocument.EnrollmentDocumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('PDF, PNG and JPEG'),
                'The message should list the supported formats. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void rejectsANullId() {
        Test.startTest();
        try {
            EnrollmentDocument.validate(null);
            System.assert(false, 'A null id should be rejected.');
        } catch (EnrollmentDocument.EnrollmentDocumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('no document'),
                'The message should name the missing document. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void rejectsAnIdThatIsNotAFile() {
        Id accountId = Id.valueOf('001000000000000AAA');

        Test.startTest();
        try {
            EnrollmentDocument.validate(accountId);
            System.assert(false, 'A non-file id should be rejected.');
        } catch (EnrollmentDocument.EnrollmentDocumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('Account'),
                'The message should name what was received. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void reportsAMissingFileRatherThanThrowingAQueryException() {
        // A syntactically valid ContentDocument id that does not exist.
        Id ghostId = Id.valueOf('069000000000000AAA');

        Test.startTest();
        try {
            EnrollmentDocument.validate(ghostId);
            System.assert(false, 'A missing file should be reported.');
        } catch (EnrollmentDocument.EnrollmentDocumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('could not be found'),
                'The message should say the file is missing. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }
}

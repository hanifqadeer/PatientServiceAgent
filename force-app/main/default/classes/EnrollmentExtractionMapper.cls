/**
 * @description Turns the text a prompt template generated into an EnrollmentExtractionResult.
 *
 *              Prompt Builder returns free text, not a schema-validated object, so this class
 *              assumes nothing: it tolerates code fences and stray prose around the JSON, treats
 *              every section and every field as possibly absent, and converts a value it cannot
 *              read into a warning rather than an exception. A single unparseable date must not
 *              cost the specialist the other thirty fields the model read correctly.
 */
public with sharing class EnrollmentExtractionMapper {
    /**
     * @description Map generated text onto the extraction DTO.
     * @param generatedText Raw text from the prompt template.
     * @return A populated result. Never null.
     * @throws ExtractionMappingException only when no JSON object can be found at all.
     */
    public static EnrollmentExtractionResult fromGeneratedText(String generatedText) {
        Map<String, Object> root = parseJsonObject(generatedText);
        EnrollmentExtractionResult result = new EnrollmentExtractionResult();

        result.documentType = str(root, 'documentType');
        result.externalReferenceNumber = str(root, 'externalReferenceNumber');

        mapPatient(asMap(root.get('patient')), result);
        mapHcp(asMap(root.get('hcp')), result);
        mapHco(asMap(root.get('hco')), result);
        mapProgram(asMap(root.get('program')), result);
        mapPayer(asMap(root.get('payer')), result);
        mapEnrollment(asMap(root.get('enrollment')), result);

        addModelWarnings(root, result);
        addReviewWarnings(result);

        result.overallConfidence = weakestSection(result);
        result.isComplete = String.isNotBlank(result.lastName) && String.isNotBlank(result.programCode);
        return result;
    }

    // ─────────────────────────── Sections ───────────────────────────

    private static void mapPatient(Map<String, Object> patient, EnrollmentExtractionResult result) {
        if (patient == null) {
            return;
        }
        result.firstName = str(patient, 'firstName');
        result.lastName = str(patient, 'lastName');
        result.dateOfBirth = parseDate(str(patient, 'dateOfBirth'), 'patient date of birth', result);
        result.phone = str(patient, 'phone');
        result.email = str(patient, 'email');
        result.street = str(patient, 'street');
        result.city = str(patient, 'city');
        result.state = str(patient, 'state');
        result.postalCode = str(patient, 'postalCode');
        result.country = str(patient, 'country');
        result.preferredLanguage = str(patient, 'preferredLanguage');
        result.communicationPreference = str(patient, 'communicationPreference');
        result.patientConfidence = confidence(patient);
    }

    private static void mapHcp(Map<String, Object> hcp, EnrollmentExtractionResult result) {
        if (hcp == null) {
            return;
        }
        result.hcpFirstName = str(hcp, 'firstName');
        result.hcpLastName = str(hcp, 'lastName');
        result.hcpNpi = str(hcp, 'npi');
        result.hcpSpecialty = str(hcp, 'specialty');
        result.hcpConfidence = confidence(hcp);
    }

    private static void mapHco(Map<String, Object> hco, EnrollmentExtractionResult result) {
        if (hco == null) {
            return;
        }
        result.hcoName = str(hco, 'name');
        result.hcoSiteType = str(hco, 'siteType');
        result.hcoTaxId = str(hco, 'taxId');
    }

    private static void mapProgram(Map<String, Object> program, EnrollmentExtractionResult result) {
        if (program == null) {
            return;
        }
        result.programCode = str(program, 'programCode');
        result.programName = str(program, 'programName');
        result.therapyArea = str(program, 'therapyArea');
        result.productName = str(program, 'productName');
        result.programConfidence = confidence(program);
    }

    private static void mapPayer(Map<String, Object> payer, EnrollmentExtractionResult result) {
        if (payer == null) {
            return;
        }
        result.payerName = str(payer, 'payerName');
        result.memberId = str(payer, 'memberId');
        result.groupNumber = str(payer, 'groupNumber');
        result.payerConfidence = confidence(payer);
    }

    private static void mapEnrollment(Map<String, Object> enrollment, EnrollmentExtractionResult result) {
        if (enrollment == null) {
            return;
        }
        result.enrollmentSource = str(enrollment, 'enrollmentSource');
        result.enrollmentDate = parseDate(str(enrollment, 'enrollmentDate'), 'enrollment date', result);
        result.patientConsentSigned = bool(enrollment, 'patientConsentSigned');
        result.prescriberSignaturePresent = bool(enrollment, 'prescriberSignaturePresent');
        result.servicesRequested = strings(enrollment, 'servicesRequested');
    }

    // ─────────────────────────── Warnings ───────────────────────────

    private static void addModelWarnings(Map<String, Object> root, EnrollmentExtractionResult result) {
        Object warnings = root.get('warnings');
        if (!(warnings instanceof List<Object>)) {
            return;
        }
        for (Object warning : (List<Object>) warnings) {
            String text = (warning == null) ? null : String.valueOf(warning).trim();
            if (String.isNotBlank(text)) {
                result.warnings.add(text);
            }
        }
    }

    /**
     * Checks the review UI cannot make for itself, because they are about what is *missing*.
     * Consent is the one that matters most: enrolling a patient who never signed is a
     * compliance problem, not a data-quality one.
     */
    private static void addReviewWarnings(EnrollmentExtractionResult result) {
        if (String.isBlank(result.lastName)) {
            result.warnings.add('No patient last name was found. Confirm this is an enrollment form.');
        }
        if (String.isBlank(result.programCode)) {
            result.warnings.add('No care program on the form matched an active program. Select one before confirming.');
        }
        if (result.patientConsentSigned == false) {
            result.warnings.add('Patient consent does not appear to be signed. Verify before enrolling.');
        }
        if (result.prescriberSignaturePresent == false) {
            result.warnings.add('No prescriber signature was detected on the form.');
        }
    }

    /** The weakest section, not an average — an average hides the one section that failed. */
    private static Decimal weakestSection(EnrollmentExtractionResult result) {
        Decimal weakest = result.patientConfidence;
        for (Decimal score : new List<Decimal>{
            result.hcpConfidence,
            result.programConfidence,
            result.payerConfidence
        }) {
            if (score < weakest) {
                weakest = score;
            }
        }
        return weakest;
    }

    // ─────────────────────────── Primitives ───────────────────────────

    /**
     * Finds the JSON object in the generated text. The prompt asks for bare JSON, but models
     * wrap it in ```json fences often enough that failing on one is not worth it.
     */
    private static Map<String, Object> parseJsonObject(String generatedText) {
        if (String.isBlank(generatedText)) {
            throw new ExtractionMappingException('The prompt template returned an empty response.');
        }

        Integer firstBrace = generatedText.indexOf('{');
        Integer lastBrace = generatedText.lastIndexOf('}');
        if (firstBrace < 0 || lastBrace <= firstBrace) {
            throw new ExtractionMappingException(
                'The prompt template did not return JSON. Check the template output instructions.'
            );
        }

        try {
            Object parsed = JSON.deserializeUntyped(generatedText.substring(firstBrace, lastBrace + 1));
            if (!(parsed instanceof Map<String, Object>)) {
                throw new ExtractionMappingException('The prompt template returned JSON that is not an object.');
            }
            return (Map<String, Object>) parsed;
        } catch (JSONException e) {
            throw new ExtractionMappingException(
                'The prompt template returned malformed JSON: ' + e.getMessage()
            );
        }
    }

    private static Map<String, Object> asMap(Object value) {
        return (value instanceof Map<String, Object>) ? (Map<String, Object>) value : null;
    }

    /** Blank and the literal string "null" both mean absent — models write both. */
    private static String str(Map<String, Object> source, String key) {
        Object value = source.get(key);
        if (value == null) {
            return null;
        }
        String text = String.valueOf(value).trim();
        return (String.isBlank(text) || text.equalsIgnoreCase('null')) ? null : text;
    }

    private static List<String> strings(Map<String, Object> source, String key) {
        List<String> values = new List<String>();
        Object raw = source.get(key);
        if (!(raw instanceof List<Object>)) {
            return values;
        }
        for (Object item : (List<Object>) raw) {
            String text = (item == null) ? null : String.valueOf(item).trim();
            if (String.isNotBlank(text) && !text.equalsIgnoreCase('null')) {
                values.add(text);
            }
        }
        return values;
    }

    private static Boolean bool(Map<String, Object> source, String key) {
        Object value = source.get(key);
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        String text = str(source, key);
        if (text == null) {
            return null;
        }
        if (text.equalsIgnoreCase('true')) {
            return true;
        }
        return text.equalsIgnoreCase('false') ? false : null;
    }

    /** Clamped to 0..1. The prompt defines the bands; nothing enforces them on the way out. */
    private static Decimal confidence(Map<String, Object> source) {
        Object value = source.get('confidence');
        if (value == null) {
            return 0.0;
        }
        try {
            Decimal score = Decimal.valueOf(String.valueOf(value));
            if (score < 0) {
                return 0.0;
            }
            return (score > 1) ? 1.0 : score.setScale(2);
        } catch (Exception e) {
            return 0.0;
        }
    }

    private static Date parseDate(String value, String fieldLabel, EnrollmentExtractionResult result) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Date.valueOf(value);
        } catch (Exception e) {
            result.warnings.add(
                'Could not read the ' + fieldLabel + ' ("' + value + '"). Enter it manually.'
            );
            return null;
        }
    }

    public class ExtractionMappingException extends Exception {}
}

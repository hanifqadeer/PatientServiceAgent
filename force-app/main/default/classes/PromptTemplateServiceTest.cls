/**
 * @description Tests for PromptTemplateService input shaping.
 *
 *              generate() itself is not covered here: ConnectApi.EinsteinLLM is not callable
 *              in a test context and has no Test.setMock support, which is exactly why the
 *              method is virtual and why AIExtractionServiceTest injects a subclass. What is
 *              testable, and worth testing, is the input shape — a File input silently sent
 *              in the wrong shape fails at runtime, not at compile time.
 */
@IsTest
private class PromptTemplateServiceTest {
    @IsTest
    static void wrapsARecordIdUnderAnIdKey() {
        Id documentId = Id.valueOf('069000000000000AAA');

        Test.startTest();
        ConnectApi.WrappedValue wrapped = PromptTemplateService.recordValue(documentId);
        Test.stopTest();

        Map<String, String> value = (Map<String, String>) wrapped.value;
        System.assertEquals(
            String.valueOf(documentId),
            value.get('id'),
            'Prompt Builder expects a record reference as a map keyed on "id".'
        );
    }

    @IsTest
    static void wrapsFreeTextAsAPlainString() {
        Test.startTest();
        ConnectApi.WrappedValue wrapped = PromptTemplateService.textValue('- programCode: ONCO-HUB-001');
        Test.stopTest();

        System.assertEquals(
            '- programCode: ONCO-HUB-001',
            (String) wrapped.value,
            'Free text inputs are passed through unwrapped.'
        );
    }

    @IsTest
    static void wrapsNullTextWithoutFailing() {
        Test.startTest();
        ConnectApi.WrappedValue wrapped = PromptTemplateService.textValue(null);
        Test.stopTest();

        System.assertNotEquals(null, wrapped, 'A null value should still produce a wrapper.');
        System.assertEquals(null, wrapped.value, 'A null text input stays null.');
    }
}

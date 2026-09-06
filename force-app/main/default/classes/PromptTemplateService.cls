/**
 * @description Thin wrapper over the Connect API for invoking Prompt Builder templates.
 *              Knows how to shape inputs and pull the generated text out of the response.
 *              It knows nothing about enrollment.
 *
 *              Everything routes through the Einstein Trust Layer, so there is no named
 *              credential, no API key and no callout to manage here — the model, the file
 *              handling and the masking are all configured on the prompt template itself.
 *
 *              Declared virtual so tests can subclass it. ConnectApi.EinsteinLLM cannot be
 *              mocked with Test.setMock and is not callable in a test context, so the only
 *              way to test the callers is to swap this out.
 */
public with sharing virtual class PromptTemplateService {
    /**
     * Identifies the calling application to the Trust Layer. 'PromptBuilderPreview' is the
     * value Salesforce documents for programmatic invocation.
     */
    private static final String APPLICATION_NAME = 'PromptBuilderPreview';

    /**
     * @description Invoke a prompt template and return its generated text.
     * @param templateApiName Developer name of the template, e.g. 'Enrollment_Document_Extraction'.
     * @param inputParams Keyed by 'Input:apiName'. Build values with recordValue()/textValue().
     * @return The first generation's text.
     */
    public virtual String generate(String templateApiName, Map<String, ConnectApi.WrappedValue> inputParams) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.applicationName = APPLICATION_NAME;
        input.isPreview = false;
        input.inputParams = inputParams;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateApiName, input);

        if (output == null || output.generations == null || output.generations.isEmpty()) {
            throw new PromptTemplateException(
                'The prompt template "' + templateApiName + '" returned no content.'
            );
        }
        return output.generations[0].text;
    }

    /**
     * @description Wrap a record id for an sObject or File input. Prompt Builder expects the
     *              record id under an 'id' key, and for a File input that id is the
     *              ContentDocument id, not the ContentVersion id.
     */
    public static ConnectApi.WrappedValue recordValue(Id recordId) {
        ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
        wrapped.value = new Map<String, String>{ 'id' => String.valueOf(recordId) };
        return wrapped;
    }

    /** @description Wrap a free text input value. */
    public static ConnectApi.WrappedValue textValue(String text) {
        ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
        wrapped.value = text;
        return wrapped;
    }

    public class PromptTemplateException extends Exception {}
}

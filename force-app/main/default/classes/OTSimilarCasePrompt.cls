public with sharing class OTSimilarCasePrompt {

    @InvocableMethod(
        label='유사 사례 프롬프트 호출'
        description='Similar_Case_Search 프롬프트 템플릿을 ConnectApi로 호출해 결과를 반환한다'
        category='T5 Dispatch Briefing'
    )
    public static List<Response> generate(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            responses.add(callPrompt(req));
        }
        return responses;
    }

    private static Response callPrompt(Request req) {
        Response res = new Response();
        try {
            ConnectApi.EinsteinPromptTemplateGenerationsInput genInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            genInput.isPreview = false;

            Map<String, ConnectApi.WrappedValue> params =
                new Map<String, ConnectApi.WrappedValue>();

            params.put('Input:Current_Case', wrap(req.currentCase));
            params.put('Input:Similar_Cases', wrap(req.similarCases));

            genInput.inputParams = params;
            genInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            genInput.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
                ConnectApi.EinsteinLlm.generateMessagesForPromptTemplate(
                    'Similar_Case_Search', genInput);

            res.summary = result.generations[0].text;
        } catch (Exception e) {
            res.summary = '[오류] ' + e.getMessage();
        }
        return res;
    }

    private static ConnectApi.WrappedValue wrap(String val) {
        ConnectApi.WrappedValue wv = new ConnectApi.WrappedValue();
        wv.value = val;
        return wv;
    }

    public class Request {
        @InvocableVariable(label='Current Case' required=true)
        public String currentCase;
        @InvocableVariable(label='Similar Cases' required=true)
        public String similarCases;
    }

    public class Response {
        @InvocableVariable(label='Summary')
        public String summary;
    }
}

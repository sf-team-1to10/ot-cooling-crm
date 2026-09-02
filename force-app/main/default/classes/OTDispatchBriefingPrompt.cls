public with sharing class OTDispatchBriefingPrompt {

    @InvocableMethod(
        label='출동 브리핑 프롬프트 호출'
        description='Dispatch_Briefing_Generator 프롬프트 템플릿을 ConnectApi로 호출해 결과를 반환한다'
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

            params.put('Input:Equipment_Name', wrap(req.equipmentName));
            params.put('Input:Measurement_History', wrap(req.measurementHistory));
            params.put('Input:Current_Reading', wrap(safe(req.currentReading)));
            params.put('Input:Peer_Comparison', wrap(safe(req.peerComparison)));
            params.put('Input:Similar_Cases_Summary', wrap(safe(req.similarCasesSummary)));

            genInput.inputParams = params;
            genInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            genInput.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
                ConnectApi.EinsteinLlm.generateMessagesForPromptTemplate(
                    'Dispatch_Briefing_Generator', genInput);

            res.briefing = result.generations[0].text;
        } catch (Exception e) {
            res.briefing = '[오류] ' + e.getMessage();
        }
        return res;
    }

    private static ConnectApi.WrappedValue wrap(String val) {
        ConnectApi.WrappedValue wv = new ConnectApi.WrappedValue();
        wv.value = val;
        return wv;
    }

    private static String safe(String val) {
        return String.isBlank(val) ? '(없음)' : val;
    }

    public class Request {
        @InvocableVariable(label='Equipment Name' required=true)
        public String equipmentName;
        @InvocableVariable(label='Measurement History' required=true)
        public String measurementHistory;
        @InvocableVariable(label='Current Reading')
        public String currentReading;
        @InvocableVariable(label='Peer Comparison')
        public String peerComparison;
        @InvocableVariable(label='Similar Cases Summary')
        public String similarCasesSummary;
    }

    public class Response {
        @InvocableVariable(label='Briefing')
        public String briefing;
    }
}

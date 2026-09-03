/**
 * Provides MessagingSession header data for the otMsSessionHeader LWC.
 * Returns session metadata fields plus the linked Case summary for the header strip.
 */
public inherited sharing class OtMsSessionHeaderController {

    /**
     * @param sessionId MessagingSession record Id
     * @return OtMsSessionHeaderDTO populated with header fields
     */
    @AuraEnabled(cacheable=true)
    public static OtMsSessionHeaderDTO getHeader(Id sessionId) {
        if (sessionId == null) {
            throw new AuraHandledException('sessionId는 필수입니다.');
        }
        try {
            List<MessagingSession> sessions = [
                SELECT Id,
                       Status,
                       StartTime,
                       EndTime,
                       MessagingChannelId,
                       MessagingChannel.MasterLabel,
                       MessagingChannel.MessageType,
                       CaseId,
                       Case.CaseNumber,
                       Case.Subject,
                       Case.Status,
                       Case.Account.Name,
                       MessagingEndUserId,
                       MessagingEndUser.Name
                FROM   MessagingSession
                WHERE  Id = :sessionId
                LIMIT  1
            ];
            if (sessions.isEmpty()) {
                throw new AuraHandledException('MessagingSession을 찾을 수 없습니다: ' + sessionId);
            }
            return buildDto(sessions[0]);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('세션 헤더 조회 중 오류가 발생했습니다: ' + e.getMessage());
        }
    }

    private static OtMsSessionHeaderDTO buildDto(MessagingSession ms) {
        OtMsSessionHeaderDTO dto = new OtMsSessionHeaderDTO();
        dto.status        = ms.Status;
        dto.startTime     = ms.StartTime;
        dto.endTime       = ms.EndTime;
        dto.channelLabel  = ms.MessagingChannel?.MasterLabel;
        dto.channelType   = ms.MessagingChannel?.MessageType;
        dto.caseId        = ms.CaseId;
        dto.caseNumber    = ms.Case?.CaseNumber;
        dto.caseSubject   = ms.Case?.Subject;
        dto.caseStatus    = ms.Case?.Status;
        dto.accountName   = ms.Case?.Account?.Name;
        dto.endUserName   = ms.MessagingEndUser?.Name;
        return dto;
    }

    /**
     * Data transfer object for MessagingSession header fields.
     */
    public class OtMsSessionHeaderDTO {
        @AuraEnabled public String  status;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime endTime;
        @AuraEnabled public String  channelLabel;
        @AuraEnabled public String  channelType;
        @AuraEnabled public Id      caseId;
        @AuraEnabled public String  caseNumber;
        @AuraEnabled public String  caseSubject;
        @AuraEnabled public String  caseStatus;
        @AuraEnabled public String  accountName;
        @AuraEnabled public String  endUserName;
    }
}

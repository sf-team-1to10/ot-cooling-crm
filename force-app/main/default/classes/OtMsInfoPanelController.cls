/**
 * Provides full MessagingSession panel data for the otMs* LWC suite.
 */
public inherited sharing class OtMsInfoPanelController {

    @AuraEnabled(cacheable=true)
    public static OtMsInfoDTO getSessionInfo(Id sessionId) {
        if (sessionId == null) {
            throw new AuraHandledException('sessionId는 필수입니다.');
        }
        try {
            List<MessagingSession> sessions = [
                SELECT Id,
                       Status,
                       StartTime,
                       EndTime,
                       Origin,
                       PreviewDetails,
                       ChannelKey,
                       MessagingChannelId,
                       MessagingChannel.MasterLabel,
                       MessagingChannel.MessageType,
                       CaseId,
                       Case.CaseNumber,
                       Case.Subject,
                       Case.Status,
                       Case.Priority,
                       Case.Type,
                       Case.Reason,
                       Case.Description,
                       Case.OwnerId,
                       Case.Owner.Name,
                       Case.Account.Id,
                       Case.Account.Name,
                       Case.AssetId,
                       Case.Asset.Name,
                       Case.Asset.SerialNumber,
                       MessagingEndUserId,
                       MessagingEndUser.Name,
                       MessagingEndUser.MessagingPlatformKey,
                       MessagingEndUser.MessagingConsentStatus,
                       MessagingEndUser.AccountId,
                       MessagingEndUser.Account.Name,
                       MessagingEndUser.ContactId,
                       MessagingEndUser.Contact.Name,
                       MessagingEndUser.Contact.Phone,
                       MessagingEndUser.Contact.Email,
                       MessagingEndUser.Contact.Account.Name
                FROM   MessagingSession
                WHERE  Id = :sessionId
                LIMIT  1
            ];
            if (sessions.isEmpty()) {
                throw new AuraHandledException('MessagingSession을 찾을 수 없습니다: ' + sessionId);
            }
            MessagingSession ms = sessions[0];
            OtMsInfoDTO dto = buildDto(ms);
            if (ms.CaseId != null) {
                Map<String, String> sla = getSlaTargets(ms.CaseId);
                dto.responseSla = sla.get('응답');
                dto.recoverySla = sla.get('복구');
            }
            return dto;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('세션 정보 조회 중 오류가 발생했습니다: ' + e.getMessage());
        }
    }

    private static OtMsInfoDTO buildDto(MessagingSession ms) {
        OtMsInfoDTO dto              = new OtMsInfoDTO();
        dto.sessionId                = ms.Id;
        dto.status                   = ms.Status;
        dto.startTime                = ms.StartTime;
        dto.endTime                  = ms.EndTime;
        dto.origin                   = ms.Origin;
        dto.previewDetails           = ms.PreviewDetails;
        dto.channelKey               = ms.ChannelKey;
        dto.channelLabel             = ms.MessagingChannel?.MasterLabel;
        dto.channelType              = ms.MessagingChannel?.MessageType;
        dto.endUserId                = ms.MessagingEndUserId;
        dto.endUserName              = ms.MessagingEndUser?.Name;
        dto.endUserPlatformKey       = ms.MessagingEndUser?.MessagingPlatformKey;
        dto.endUserConsentStatus     = ms.MessagingEndUser?.MessagingConsentStatus;
        dto.endUserAccountId         = ms.MessagingEndUser?.AccountId;
        dto.endUserAccountName       = ms.MessagingEndUser?.Account?.Name;
        dto.contactId                = ms.MessagingEndUser?.ContactId;
        dto.contactName              = ms.MessagingEndUser?.Contact?.Name;
        dto.contactPhone             = ms.MessagingEndUser?.Contact?.Phone;
        dto.contactEmail             = ms.MessagingEndUser?.Contact?.Email;
        dto.contactAccountName       = ms.MessagingEndUser?.Contact?.Account?.Name;
        dto.caseId                   = ms.CaseId;
        dto.caseNumber               = ms.Case?.CaseNumber;
        dto.caseSubject              = ms.Case?.Subject;
        dto.caseStatus               = ms.Case?.Status;
        dto.casePriority             = ms.Case?.Priority;
        dto.caseType                 = ms.Case?.Type;
        dto.caseReason               = ms.Case?.Reason;
        dto.caseDescription          = ms.Case?.Description;
        dto.caseOwnerName            = ms.Case?.Owner?.Name;
        dto.accountId                = ms.Case?.Account?.Id;
        dto.accountName              = ms.Case?.Account?.Name;
        dto.assetId                  = ms.Case?.AssetId;
        dto.assetName                = ms.Case?.Asset?.Name;
        dto.assetSerialNumber        = ms.Case?.Asset?.SerialNumber;
        return dto;
    }

    private static Map<String, String> getSlaTargets(Id caseId) {
        Map<String, String> result = new Map<String, String>();
        for (CaseMilestone m : [
            SELECT MilestoneType.Name, TargetDate, StartDate
            FROM   CaseMilestone
            WHERE  CaseId = :caseId
              AND  TargetDate != null
              AND  StartDate  != null
            WITH   USER_MODE
        ]) {
            Long durMin = (m.TargetDate.getTime() - m.StartDate.getTime()) / 60000;
            result.put(m.MilestoneType.Name, formatDuration(durMin));
        }
        return result;
    }

    private static String formatDuration(Long minutes) {
        if (minutes < 60) return minutes + '분';
        Long hours = minutes / 60;
        Long rem   = Math.mod(minutes, 60);
        return rem == 0 ? hours + '시간' : hours + '시간 ' + rem + '분';
    }

    public class OtMsInfoDTO {
        @AuraEnabled public Id       sessionId;
        @AuraEnabled public String   status;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime endTime;
        @AuraEnabled public String   origin;
        @AuraEnabled public String   previewDetails;
        @AuraEnabled public String   channelKey;
        @AuraEnabled public String   channelLabel;
        @AuraEnabled public String   channelType;
        @AuraEnabled public Id       endUserId;
        @AuraEnabled public String   endUserName;
        @AuraEnabled public String   endUserPlatformKey;
        @AuraEnabled public String   endUserConsentStatus;
        @AuraEnabled public Id       endUserAccountId;
        @AuraEnabled public String   endUserAccountName;
        @AuraEnabled public Id       contactId;
        @AuraEnabled public String   contactName;
        @AuraEnabled public String   contactPhone;
        @AuraEnabled public String   contactEmail;
        @AuraEnabled public String   contactAccountName;
        @AuraEnabled public Id       caseId;
        @AuraEnabled public String   caseNumber;
        @AuraEnabled public String   caseSubject;
        @AuraEnabled public String   caseStatus;
        @AuraEnabled public String   casePriority;
        @AuraEnabled public String   caseType;
        @AuraEnabled public String   caseReason;
        @AuraEnabled public String   caseDescription;
        @AuraEnabled public String   caseOwnerName;
        @AuraEnabled public Id       accountId;
        @AuraEnabled public String   accountName;
        @AuraEnabled public Id       assetId;
        @AuraEnabled public String   assetName;
        @AuraEnabled public String   assetSerialNumber;
        @AuraEnabled public String   responseSla;
        @AuraEnabled public String   recoverySla;
    }
}

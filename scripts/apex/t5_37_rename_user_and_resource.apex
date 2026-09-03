// T5-37: 서정비 User + 그 ServiceResource 이름을 강시공으로 변경.
// 지금 로그인 세션에도 즉시 반영됨. Email/RelatedRecordId 는 그대로.
Id userId = '005bm00000UFJyjAAH';
Id srId = '0Hnbm000000ST8jCAG';

User u = new User(Id = userId, FirstName = '시공', LastName = '강', Alias = 'kang01');
update u;

ServiceResource sr = new ServiceResource(Id = srId, Name = '강시공');
update sr;

User after = [SELECT Name, Alias, Email FROM User WHERE Id = :userId];
ServiceResource srAfter = [SELECT Name, IsActive FROM ServiceResource WHERE Id = :srId];

System.debug('=== T5-37 User/Resource rename 완료 ===');
System.debug('User Name: ' + after.Name + ' · Alias: ' + after.Alias + ' · Email: ' + after.Email);
System.debug('ServiceResource: ' + srAfter.Name + ' · Active: ' + srAfter.IsActive);

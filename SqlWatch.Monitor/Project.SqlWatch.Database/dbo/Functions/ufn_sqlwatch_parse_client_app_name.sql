﻿CREATE FUNCTION [dbo].[ufn_sqlwatch_parse_client_app_name] 
(
	@client_app_name varchar(255)
) 
RETURNS varchar(255) with schemabinding
AS
BEGIN
	return
		'Not Implemented'
		--case 
			--check if the passed string contains what we need. if it does, then filter out the binary string and replace it with the actual agent job name.
			--otherwise just return what was passed:
			--when @client_app_name like 'SQLAGent - TSQL JobStep%' then replace(w.client_app_name collate DATABASE_DEFAULT,left(replace(w.client_app_name collate DATABASE_DEFAULT,'SQLAgent - TSQL JobStep (Job ',''),34),j.name) 
			--else @client_app_name end
END

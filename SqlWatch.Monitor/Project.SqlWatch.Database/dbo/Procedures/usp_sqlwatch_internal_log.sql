﻿CREATE PROCEDURE [dbo].[usp_sqlwatch_internal_log]
	@process_name			nvarchar(max) = null,
	@process_stage			nvarchar(max),
	@process_message		nvarchar(max),
	@process_message_type	nvarchar(max),
	@proc_id				int = null
as

SET XACT_ABORT ON
SET NOCOUNT ON 

begin try	

	declare @snapshot_time datetime2(0)

	if @process_message_type = 'INFO' and dbo.ufn_sqlwatch_get_config_value(7, null) <> 1
		begin
			return
		end

	if @process_name is null and @proc_id is not null
		begin
			set @process_name = OBJECT_NAME(@proc_id)
		end

	insert into dbo.[sqlwatch_app_log] (
		 [process_name]			
		,[process_stage]			
		,[process_message]		
		,[process_message_type]	
		,[spid]					
		,[process_login]			
		,[process_user]			
		,[ERROR_NUMBER]
		,[ERROR_SEVERITY]
		,[ERROR_STATE]
		,[ERROR_PROCEDURE]
		,[ERROR_LINE]
		,[ERROR_MESSAGE]
	)
	values (
		@process_name, @process_stage, @process_message, @process_message_type,
		@@SPID, SYSTEM_USER, USER
			, case when @process_message_type <> 'INFO' then ERROR_NUMBER() else null end
			, case when @process_message_type <> 'INFO' then ERROR_SEVERITY() else null end
			, case when @process_message_type <> 'INFO' then ERROR_STATE() else null end
			, case when @process_message_type <> 'INFO' then ERROR_PROCEDURE() else null end
			, case when @process_message_type <> 'INFO' then ERROR_LINE() else null end
			, case when @process_message_type <> 'INFO' then ERROR_MESSAGE() else null end
	)

--	begin
--		Print char(10) + '>>>---- ' + @process_message_type + ' ------------------------------------' + char(10) +
--'Time: ' + convert(nvarchar(23),@snapshot_time,121) + char(10) + 
--'Process Name: ' + @process_name + char(10) + 
--'Stage: ' + @process_stage + char(10) +  
--'Message: ' + @process_message + char(10) + 
--'Message Type: ' + @process_message_type + char(10) + 
--case when @process_message_type <> 'INFO' then 'Error: ' + [dbo].[ufn_sqlwatch_get_error_detail_text] () else '' end + char(10) +
--'---- ' + @process_message_type + ' ------------------------------------<<<' + char(10)
--	end 

end try
begin catch
	--fatal error in the error loggin procedure
	declare @message nvarchar(max)
	set @message = [dbo].[ufn_sqlwatch_get_error_detail_text] ()
	raiserror (@message,16,1)
	print @message
end catch
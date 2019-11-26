﻿CREATE PROCEDURE [dbo].[usp_sqlwatch_internal_process_actions] (
	@sql_instance varchar(32) = @@SERVERNAME,
	@check_id smallint,
	@action_id smallint,
	@check_status varchar(50),
	@check_value decimal(28,2),
	@check_snapshot_time datetime2(0),
	@check_description nvarchar(max) = null,
	@check_name nvarchar(max),
	@check_threshold_warning varchar(100) = null,
	@check_threshold_critical varchar(100) = null
	)
as

Print '   Action (Id: ' + convert(varchar(10),@action_id) + ')'

/* 
-------------------------------------------------------------------------------------------------------------------
	[usp_sqlwatch_internal_process_actions]

	Abstract: 

	actions expect the following parameters:
	{SUBJECT} and {BODY}

	however, each can have its own template.
	for example, when using email action, we could have more content in the body
	and when using pushover we could limit it to most important informations.


	Version:
		1.0 2019-11-08 - Marcin Gminski
------------------------------------------------------------------------------------------------------------------- 
*/


declare @action_type varchar(200) = 'NONE',
		@action_every_failure bit,
		@action_recovery bit,
		@action_repeat_period_minutes smallint,
		@action_hourly_limit tinyint,
		@action_template_id smallint,
		@last_action_time datetime,
		@action_count_last_hour smallint,
		@subject nvarchar(max),
		@body nvarchar(max),
		@report_id smallint,
		@content_info varbinary(128),
		@action_attributes nvarchar(max) = '',
		@error_message nvarchar(max) = ''

--need to this so we can detect the caller in [usp_sqlwatch_internal_process_reports] to avoid circular ref.
select @content_info = convert(varbinary(128),convert(varchar(max),@action_id))
set CONTEXT_INFO @content_info

set @action_attributes = @action_attributes + '
	ContentInfo="' + isnull(convert(varchar(max),@action_id),'') + '"'

-------------------------------------------------------------------------------------------------------------------
-- Get action parameters:
-------------------------------------------------------------------------------------------------------------------
select 
		@action_every_failure = [action_every_failure]
	,	@action_recovery = [action_recovery]
	,	@action_repeat_period_minutes = [action_repeat_period_minutes]
	,	@action_hourly_limit = [action_hourly_limit]
	,	@action_template_id = [action_template_id]
from [dbo].[sqlwatch_config_check_action]
where [check_id] = @check_id
and [action_id] = @action_id
--and sql_instance = @@SERVERNAME

set @action_attributes = @action_attributes + '
	ActionEveryFailure="' + isnull(convert(varchar(10),@action_every_failure),'') + '"
	ActionRecovery="' + isnull(convert(varchar(10),@action_recovery),'') + '"
	ActionRepeatPeriodMinutes="' + isnull(convert(varchar(10),@action_repeat_period_minutes),'') +'"
	ActionHourlyLimit="' + isnull(convert(varchar(10),@action_hourly_limit),'') + '"
	ActionTemplateId="' + isnull(convert(varchar(10),@action_template_id),'') + '"'

-------------------------------------------------------------------------------------------------------------------
-- each check has limit of actions per hour to avoid flooding:
-------------------------------------------------------------------------------------------------------------------
select 
	  @last_action_time = max([snapshot_time])
	, @action_count_last_hour = count(case when [snapshot_time] > dateadd(hour,-1,getutcdate()) then 1 else null end)
from [dbo].[sqlwatch_logger_check_action]
where [check_id] = @check_id
and [action_id] = @action_id
and action_type <> 'NONE'
and sql_instance = @@SERVERNAME

set @action_attributes = @action_attributes + '
	LastActionTime="' + isnull(convert(varchar(23),@last_action_time,121),'') + '"
	ActionCountLastHour="' + isnull(convert(varchar(10),@action_count_last_hour),'') + '"'

-------------------------------------------------------------------------------------------------------------------
-- We need to know if we are dealing with a new, repeated or recovered action. For this, we have to check
-- previous checks where action was requested
-------------------------------------------------------------------------------------------------------------------

select @action_type = case 

	-------------------------------------------------------------------------------------------------------------------
	-- when the current status is not OK and the previous status was OK, its a new notification:
	-------------------------------------------------------------------------------------------------------------------
	when @check_status <> 'OK' and isnull(last_check_status,'OK') = 'OK' then 'NEW'

	-------------------------------------------------------------------------------------------------------------------
	-- if previous status is NOT ok and current status is OK the check has recovered from fail to success.
	-- we can send an email notyfing DBAs that the problem has gone away
	-------------------------------------------------------------------------------------------------------------------
	when @check_status = 'OK' and isnull(last_check_status,'OK') <> 'OK' and @action_recovery = 1 then 'RECOVERY'

	-------------------------------------------------------------------------------------------------------------------
	-- retrigger if the value has changed and the status is not OK
	-- this is handy if we want to monitor every change after it has failed. for example we can set to monitor
	-- if number of logins is greater than 5 so if someone creates a new login we will get an email and then every time
	-- new login is created

	-- this however will not work in situations where we want a notification for ongoing blocking chains or failed jobs
	-- where there the count does not change. i.e. job A fails and then recovers but job B fails instead. The overall 
	-- count of jailed jobs at any given time is still 1. in such instance we can ste a reminder to 1 minute.
	-------------------------------------------------------------------------------------------------------------------
	when @check_status <> 'OK' and isnull(last_check_status,'OK') <> 'OK' 
		 and (last_check_value is null or @check_value <> last_check_value) and @action_every_failure = 1 then 'REPEAT'

	-------------------------------------------------------------------------------------------------------------------
	-- if the previous status is the same as the current status we would not normally send another email
	-- however, we can do if we set retrigger time. for example, we can be sending repeated alerts every hour so 
	-- they do not get forgotten about. 
	-------------------------------------------------------------------------------------------------------------------
	when @check_status <> 'OK' and last_check_status = @check_status and (@action_repeat_period_minutes is not null 
		and datediff(minute,@last_action_time,getdate()) > @action_repeat_period_minutes) then 'REPEAT'

	else 'NONE' end
from [dbo].[sqlwatch_meta_check]
where [check_id] = @check_id
and sql_instance = @@SERVERNAME

set @action_attributes = @action_attributes + '
	ActionType="' + isnull(@action_type,'') + '"'

-------------------------------------------------------------------------------------------------------------------
-- now we know what action we are dealing with, we can build template:
-------------------------------------------------------------------------------------------------------------------
select 
	 @subject = case @action_type 
			when 'NEW' then action_template_fail_subject
			when 'RECOVERY' then action_template_recover_subject
			when 'REPEAT' then action_template_repeat_subject
		else 'UNDEFINED' end
	,@body = case @action_type
			when 'NEW' then action_template_fail_body
			when 'RECOVERY' then action_template_recover_body
			when 'REPEAT' then action_template_repeat_body
		else 'UNDEFINED' end		
from [dbo].[sqlwatch_config_check_action_template]
where action_template_id = @action_template_id
--and sql_instance = @@SERVERNAME

set @action_attributes = @action_attributes + '
	SubjectTemplate="' + isnull(replace(@subject,'''',''''''),'') + '"
	BodyTemplate="' + isnull(replace(@body,'''',''''''),'') + '"'

-------------------------------------------------------------------------------------------------------------------
-- Get action details and add to the queue:
-------------------------------------------------------------------------------------------------------------------

if @action_count_last_hour > @action_hourly_limit
	begin
		Print 'Action count (' + convert(varchar(10),@action_count_last_hour) + ') exeeded hourly limit (' + convert(varchar(10),@action_hourly_limit) + '.'
		set @action_attributes = @action_attributes + '
	ErrorMessage="Action count exceeded hourly allowed limit."'
		GoTo LogAction
	end


-------------------------------------------------------------------------------------------------------------------
-- set {SUBJECT} and {BODY}
-------------------------------------------------------------------------------------------------------------------
if @action_type  <> 'NONE'
	begin
		--an action with arbitrary executable must have the following parameters:
		--{SUBJECT} and {BODY}
		--on top of it, an action will have a template that can have one of the below parameters so need to substitute them here:
		select @subject = 
			replace(
				replace(
					replace(
						replace(
							replace(
								replace(
									replace(
										replace(
											replace(
												replace(
													replace(
														replace(
															replace(
																replace(@subject,'{CHECK_STATUS}',@check_status)
															,'{CHECK_NAME}',check_name)
														,'{SQL_INSTANCE}',@@SERVERNAME)
													,'{CHECK_ID}',convert(varchar(10),cc.check_id))
												,'{CHECK_STATUS}',@check_status)
											,'{CHECK_VALUE}',convert(varchar(10),@check_value))
										,'{CHECK_LAST_VALUE}',isnull(convert(varchar(10),cc.last_check_value),'N/A'))
									,'{CHECK_LAST_STATUS}',isnull(cc.last_check_status,'N/A'))
								,'{LAST_STATUS_CHANGE}',isnull(convert(varchar(23),cc.last_status_change_date,121),'Never'))
							,'{CHECK_TIME}',convert(varchar(23),getdate(),121))
						,'{THRESHOLD_WARNING}',isnull(cc.check_threshold_warning,''))
					,'{THRESHOLD_CRITICAL}',isnull(cc.check_threshold_critical,''))
				,'{CHECK_DESCRIPTION}',isnull(cc.check_description,''))
			,'{CHECK_QUERY}',isnull(replace(cc.check_query,'''',''''''),''))

			, @body = 
			replace(
				replace(
					replace(
						replace(
							replace(
								replace(
									replace(
										replace(
											replace(
												replace(
													replace(
														replace(
															replace(
																replace(@body,'{CHECK_STATUS}',@check_status)
															,'{CHECK_NAME}',check_name)
														,'{SQL_INSTANCE}',@@SERVERNAME)
													,'{CHECK_ID}',convert(varchar(10),cc.check_id))
												,'{CHECK_STATUS}',@check_status)
											,'{CHECK_VALUE}',convert(varchar(10),@check_value))
										,'{CHECK_LAST_VALUE}',isnull(convert(varchar(10),cc.last_check_value),'N/A'))
									,'{CHECK_LAST_STATUS}',isnull(cc.last_check_status,'N/A'))
								,'{LAST_STATUS_CHANGE}',isnull(convert(varchar(23),cc.last_status_change_date,121),'Never'))
							,'{CHECK_TIME}',convert(varchar(23),getdate(),121))
						,'{THRESHOLD_WARNING}',isnull(cc.check_threshold_warning,'None'))
					,'{THRESHOLD_CRITICAL}',isnull(cc.check_threshold_critical,''))
				,'{CHECK_DESCRIPTION}',isnull(cc.check_description,''))
			,'{CHECK_QUERY}',isnull(replace(cc.check_query,'''',''''''),''))

		from [dbo].[sqlwatch_meta_check] cc
		where cc.check_id = @check_id
		and cc.sql_instance = @@SERVERNAME

		set @action_attributes = @action_attributes + '
	Subject="' + isnull(replace(replace(@subject,'''',''''''),'"','\"'),'') + '"
	Body="' + isnull(replace(replace(@body,'''',''''''),'"','\"'),'') + '"'


		insert into [dbo].[sqlwatch_meta_action_queue] (sql_instance, [action_exec_type], [action_exec])
		select @@SERVERNAME, [action_exec_type], replace(replace([action_exec],'{SUBJECT}',@subject),'{BODY}',@body)
		from [dbo].[sqlwatch_config_action]
		where action_id = @action_id
		and [action_enabled] = 1
		and [action_exec] is not null --null action exec can only be for reports but they are processed below
		--and sql_instance = @@SERVERNAME

		--is this action calling a report or an arbitrary exec?
		select @report_id = action_report_id 
		from [dbo].[sqlwatch_config_action] where action_id = @action_id

		if @report_id is not null
			begin
				--if we have action that calls a report, call the report here:
				begin try
					exec [dbo].[usp_sqlwatch_internal_process_reports] 
						 @report_id = @report_id
						,@check_status = @check_status
						,@check_value = @check_value
						,@check_name = @check_name
						,@subject = @subject
						,@body = @body
						,@check_threshold_warning = @check_threshold_warning
						,@check_threshold_critical = @check_threshold_critical

					set @action_attributes = @action_attributes + '
	ReportId="' + convert(varchar(10),@report_id) + '"'
				end try
				begin catch
					select @error_message = @error_message + '
' + convert(varchar(23),getdate(),121) + ': ActionID: ' + convert(varchar(10),@action_id) + ' ReportID: ' + convert(varchar(10),@report_id) + '
		ERROR_NUMBER: ' + isnull(convert(varchar(10),ERROR_NUMBER()),'') + '
        ERROR_SEVERITY : ' + isnull(convert(varchar(max),ERROR_SEVERITY()),'') + '
        ERROR_STATE : ' + isnull(convert(varchar(max),ERROR_STATE()),'') + '   
        ERROR_PROCEDURE : ' + isnull(convert(varchar(max),ERROR_PROCEDURE()),'') + '   
        ERROR_LINE : ' + isnull(convert(varchar(max),ERROR_LINE()),'') + '   
        ERROR_MESSAGE : ' + isnull(convert(varchar(max),ERROR_MESSAGE()),'') + ''
				end catch
			end
	end

 LogAction:

 set @action_attributes = '{' + @action_attributes + '
}'


--log action for each check. This is so we can track how many actions are being executed per each check to satisfy 
--the [action_hourly_limit] parameter and to have an overall visibility of what checks trigger what actions. 
--This table needs a minimum of 1 hour history.

--by default, we are NOT logging actions that have no action to do, only those that are triggering a valid action or have error:
if @action_type <> 'NONE'
	begin
		insert into [dbo].[sqlwatch_logger_check_action] ([sql_instance], [snapshot_type_id], [check_id], [action_id], [snapshot_time], [action_type], [action_attributes])
		select @@SERVERNAME, 18, @check_id, @action_id, @check_snapshot_time, @action_type, @action_attributes
	end


if nullif(@error_message,'') is not null
	begin
		set @error_message = 'Errors during action execution (' + OBJECT_NAME(@@PROCID) + '): 
' + @error_message

		--print all errors and terminate the batch which will also fail the agent job for the attention:
		raiserror ('%s',16,1,@error_message)
	end
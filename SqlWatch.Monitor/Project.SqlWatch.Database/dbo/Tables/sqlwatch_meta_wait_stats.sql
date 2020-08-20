﻿CREATE TABLE [dbo].[sqlwatch_meta_wait_stats]
(
	[sql_instance] varchar(32) not null,
	[wait_type] nvarchar(60) not null, 
	[wait_type_id] smallint identity(1,1) not null,
	[date_updated] datetime not null constraint df_sqlwatch_meta_wait_stats_updated default (getutcdate()),
	constraint pk_sqlwatch_meta_wait_stats primary key (
		[sql_instance], [wait_type_id]
		),
	constraint uq_sqlwatch_meta_wait_stats_wait_type unique ([sql_instance],[wait_type]),
	constraint fk_sqlwatch_meta_wait_stats_server foreign key ([sql_instance])
		references [dbo].[sqlwatch_meta_server] ([servername]) on delete cascade
)
go

create nonclustered index idx_sqlwatch_meta_wait_stats_1 on [dbo].[sqlwatch_meta_wait_stats] ([date_updated])
go

create trigger trg_sqlwatch_meta_wait_stats_last_updated
	on [dbo].[sqlwatch_meta_wait_stats]
	for insert,update
	as
	begin
		set nocount on;
		set xact_abort on;

		update t
			set date_updated = getutcdate()
		from [dbo].[sqlwatch_meta_wait_stats] t
		inner join inserted i
			on i.[sql_instance] = t.[sql_instance]
			and i.[wait_type_id] = t.[wait_type_id]
			and i.[sql_instance] = @@SERVERNAME
	end
go
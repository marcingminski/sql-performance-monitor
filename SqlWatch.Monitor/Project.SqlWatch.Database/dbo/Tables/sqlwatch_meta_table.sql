﻿CREATE TABLE [dbo].[sqlwatch_meta_table]
(
	[sql_instance] varchar(32) not null,
	[sqlwatch_database_id] smallint not null,
	[sqlwatch_table_id] int identity(1,1) not null,
	[table_name] nvarchar(512), --table lenght is 128 in SQL2008 and 256 in newer versions but as we also keep schema name here we need to account for that too.
	[table_type] nvarchar(128),
	[date_first_seen] datetime not null constraint df_sqlwatch_meta_table_date_created default (getutcdate()),
	[date_last_seen] datetime not null constraint df_sqlwatch_meta_table_last_seen default (getutcdate()),
	--[is_record_deleted] bit
	constraint pk_sqlwatch_meta_database_table primary key clustered (
		[sql_instance], [sqlwatch_database_id], [sqlwatch_table_id]
		),
	constraint uq_sqlwatch_meta_table_table unique (
		[sql_instance], [sqlwatch_database_id], [table_name]
		),
	constraint fk_sqlwatch_meta_table_database foreign key ([sql_instance],[sqlwatch_database_id]) references [dbo].[sqlwatch_meta_database] ([sql_instance],[sqlwatch_database_id]) on delete cascade
)

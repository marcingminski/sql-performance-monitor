﻿CREATE TABLE [dbo].[sqlwatch_logger_disk_utilisation_database]
(
	[sqlwatch_database_id] uniqueidentifier not null ,
	[database_size_bytes] bigint,
	[unallocated_space_bytes] bigint,
	[reserved_bytes] bigint,
	[data_bytes] bigint,
	[index_size_bytes] bigint,
	[unused_bytes] bigint,
	[log_size_total_bytes] bigint,
	[log_size_used_bytes] bigint,
	[snapshot_time] datetime,
	[snapshot_type_id] tinyint,
	[sql_instance] nvarchar(25) default @@SERVERNAME,
	constraint PK_logger_disk_util_database
		primary key clustered ([snapshot_time],[snapshot_type_id],[sql_instance], [sqlwatch_database_id]),
	constraint FK_logger_disk_util_database_database
		foreign key ([sql_instance],[sqlwatch_database_id])
		references [dbo].[sqlwatch_meta_database] ([sql_instance],[sqlwatch_database_id])
		on delete cascade,
	constraint FK_logger_disk_util_database_snapshot 
		foreign key ([snapshot_time],[snapshot_type_id],[sql_instance])
		references [dbo].[sqlwatch_logger_snapshot_header] ([snapshot_time],[snapshot_type_id],[sql_instance])
		on delete cascade on update cascade
)
go

CREATE NONCLUSTERED INDEX idx_sqlwatch_disk_util_database_001
ON [dbo].[sqlwatch_logger_disk_utilisation_database] ([sql_instance])
INCLUDE ([snapshot_time],[snapshot_type_id])
﻿CREATE TABLE [dbo].[sqlwatch_meta_server]
(
	[physical_name] nvarchar(128),
	[servername] varchar(32) not null,
	[service_name] nvarchar(128),
	[local_net_address] varchar(50),
	[local_tcp_port] varchar(50),
	[utc_offset_minutes] int not null constraint df_sqlwatch_meta_server_offset default (DATEDIFF(mi, GETUTCDATE(), GETDATE())),
	[sql_version] nvarchar(2048),
	constraint pk_sqlwatch_meta_server primary key clustered (
		[servername]
		)
)

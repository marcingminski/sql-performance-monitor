﻿CREATE FUNCTION [dbo].[ufn_sqlwatch_get_database_create_date]
(
	@database_name nvarchar(256),
	@create_date datetime
)
RETURNS datetime with schemabinding
AS
BEGIN
	RETURN (select case when @database_name = 'tempdb' then '1970-01-01' else @create_date end)
END

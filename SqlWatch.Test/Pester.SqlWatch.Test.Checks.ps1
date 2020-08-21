﻿param(
    $SqlInstance,
    $SqlWatchDatabase,
    $MinSqlUpHours,
    $LookBackHours
)

$sql = "select datediff(hour,sqlserver_start_time,getdate()) from sys.dm_os_sys_info"
$result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql
$SqlUpHours = $result.Column1 #| Should -BeGreaterThan 4 -Because 'Recently restarted Sql Instance may not provide accurate test results'

$Checks = @(); #thanks Rob https://sqldbawithabeard.com/2017/11/28/2-ways-to-loop-through-collections-in-pester/
$Checks = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query "select check_id, check_name from [dbo].[sqlwatch_config_check]"

$TestCases = @();
$Checks.ForEach{$TestCases += @{check_name = $_.check_name }}

Describe 'Failed Checks' {

    Context "Checking for checks that have failed to execute with the CHECK_ERROR outcome" {
    
        It 'Check [<check_name>] executions should never return status of CHECK ERROR' -TestCases $TestCases {

            Param($check_name)

            if ($SqlUpHours -lt $MinSqlUpHours) {

                It -Skip "SQL Server has recently been restared. For accureate results, please allow minimum of 6 hours before running these tests."

            } else {

                $sql = "declare @starttime datetime; 
    
                select @starttime=sqlserver_start_time 
                from sys.dm_os_sys_info
    
                select count(*) 
                    from [dbo].[sqlwatch_config_check] cc 
                    left join [dbo].[sqlwatch_logger_check] lc 
                        on cc.check_id = lc.check_id 
                    where snapshot_time > dateadd(hour,-$($LookBackHours),getutcdate()) 
                    and cc.check_name = '$($check_name)' 
                    and lc.check_status like '%ERROR%'
                    --skip records after restart as Perf counters will be empty right after restart.
                    and lc.snapshot_time > dateadd(minute,2,@starttime)
                    "

                $result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql
                $result.Column1 | Should -Be 0 -Because 'The check results should be "OK", "WARNING" or "CRITICAL". However, checks that fail to execute or return value that is out of bound, will return "CHECK ERROR" status.'

            }
        }
    }

    Context "Checking if checks have outcome" {
    
      It 'Check [<check_name>] should have an outcome' -TestCases $TestCases {
    

        Param($check_name) 

        if ($SqlUpHours -lt $MinSqlUpHours) {

            It -Skip "SQL Server has recently been restared. For accureate results, please allow minimum of 6 hours before running these tests."

        } else {

            $sql = "select last_check_status from [dbo].[sqlwatch_meta_check] where check_name = '$($check_name)'"

            $result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql
            $result.last_check_status | Should -BeIn ("OK","WARNING","CRITICAL","CHECK ERROR") -Because 'Checks must return an outcome, it should be either "OK", "WARNING", "CRITICAL" or "CHECK_ERROR"'

        }
      
      }

    }

    Context "Checking for checks that do not respect the execution frequency parameter " {

         It 'Check [<check_name>] should respect execution frequency setting' -TestCases $TestCases {
     
            Param($check_name) 

            if ($SqlUpHours -lt $MinSqlUpHours) {

                It -Skip "SQL Server has recently been restared. For accureate results, please allow minimum of 6 hours before running these tests."

            } else {

                $sql = "select check_frequency_minutes=isnull(check_frequency_minutes,1) from [dbo].[sqlwatch_config_check] where check_name = '$($check_name)'"
                $check_frequency_minutes = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql

                $sql = "select cc.check_id, lc.snapshot_time, RN=ROW_NUMBER() over (partition by cc.check_id order by lc.snapshot_time)
            into #t
            from [dbo].[sqlwatch_logger_check] lc
            inner join dbo.sqlwatch_config_check cc
	            on lc.check_id = cc.check_id
            where snapshot_time > dateadd(hour,-$($LookBackHours),getutcdate())
            and cc.check_name = '$($check_name)'

            create clustered index icx_tmp_t on #t (snapshot_time)

            select
	            min_check_frequency_minutes_calculated=ceiling(avg(datediff(second,c1.snapshot_time,c2.snapshot_time)/60.0))
            from #t c1
            left join #t c2
	            on c1.check_id = c2.check_id
	            and c1.RN = c2.RN -1
            "

                # Because sql agent is syncronous, there is no guarantee that checks will always run at the same interval. There will be +/- few seconds or even a couple of minutes
                # If the check takes longer to execute, the gap between the second execution will be smaller than it should be. 
                # We are going to allow some deviation of +/- 1 minute
                $minvalue=$check_frequency_minutes.check_frequency_minutes-1
                $maxvalue=$check_frequency_minutes.check_frequency_minutes+1
                $value=$check_frequency_minutes.check_frequency_minutes
                $result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql
                $result.min_check_frequency_minutes_calculated | Should -BeIn ($minvalue,$value,$maxvalue) -Because 'The agent job that invokes the check engine runs every 1 minute but not all checks should run every 1 minute. There is a [check_frequency_minutes] column that tells us how often each check should run. This value must be respected otherwise all checks will run every 1 minute which will create additional load on the server'

            }
          }
    }
}

$TimeFields = @();
$TimeFields = "select column=TABLE_SCHEMA + '.' + TABLE_NAME + '.' + COLUMN_NAME from INFORMATION_SCHEMA.COLUMNS where DATA_TYPE LIKE '%time%'"

$TestCases = @();
$TimeFields.ForEach{$TestCases += @{column = $_.column}}

Describe 'Test database design' {

    $sql = "select datediff(hour,getutcdate(),getdate())"
    $result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql;

    if ($result.Column1 -ge 0) {
        It -Skip "The server must be in a time zone behind the UTC time zone in order to validate what time values are being written. This will allow us to assume that if the written value is in the future, the value is Not a UTC zone.";
    } else {
        It 'Datetime values in <column> should be UTC' -TestCases $TestCases {
            Param($column)
        
            $sql = "select LOCAL_TIME=GETDATE(), UTC_TIME=GETUTCDATE(), TABLE_NAME,COLUMN_NAME 
            from INFORMATION_SCHEMA.COLUMNS 
            where TABLE_SCHEMA + '.' + TABLE_NAME + '.' + COLUMN_NAME = '$($column)'"

            $result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql;

            $sql = "select top 1 datediff(hour,GETUTCDATE(),$($result.COLUMN_NAME)) from [$($result.$TABLE_NAME)] order by $($result.COLUMN_NAME) desc";
            $result.Column1 | should -Not -BeGreaterThan 0 -Because 'Values in the future indicate incorrect time zone'    
        }
    }
}

Describe 'Test Check Results' {

    It 'The Latest Data Backup Check should return correct result' {
        ## Use dbatools as a baseline
        $LastFullBackup = Get-DbaLastBackup -SqlInstance $SqlInstance | Sort-Object LastFullBackup -Descending | Select-Object -first 1 
        $LastDiffBackup = Get-DbaLastBackup -SqlInstance $SqlInstance | Sort-Object LastDiffBackup -Descending | Select-Object -first 1 

        $LastFullBackupAgeDays = $(New-TimeSpan -Start $LastFullBackup.LastFullBackup -End (Get-Date)).TotalDays
        $LastDiffBackupAgeDays = $(New-TimeSpan -Start $LastDiffBackup.LastDiffBackup -End (Get-Date)).TotalDays        

        if ($LastDiffBackupAgeDays -lt $LastFullBackupAgeDays) {
            [int]$LastDataBackupAgeDays = $LastDiffBackupAgeDays
        } else {
            [int]$LastDataBackupAgeDays = $LastFullBackupAgeDays
        }

        ## this is the sql query from the check itself as we have to compare live values:
        ## check_id -18        
        $sql = "select check_query from dbo.sqlwatch_meta_check where check_id = -18"
        $result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql;

        $sql = $result.check_query -replace "@output","output"
        $result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql;

        $result.output | should -Be $LastDataBackupAgeDays 
    }

    It 'The Latest Log Backup Check should return correct result' {
        ## Use dbatools as a baseline
        $LastLogBackup = Get-DbaLastBackup -SqlInstance SQL-1 | Sort-Object LastLogBackup -Descending | Select-Object -first 1 

        [int]$LastLogBackupAgeMinutes = $(New-TimeSpan -Start $LastLogBackup.LastLogBackup -End (Get-Date)).TotalMinutes

        ## this is the sql query from the check itself as we have to compare live values:
        ## check_id -17
        $sql = "select check_query from dbo.sqlwatch_meta_check where check_id = -17"
        $result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql;

        $sql = $result.check_query -replace "@output","output"
        $result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql;

        $result.output | should -Be $LastLogBackupAgeMinutes 
    }
}

Describe 'Data Retention' {

    Context 'Checking Snapshot Retention Policy is being applied' {

        $SnapshotTypes = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query "select * from sqlwatch_config_snapshot_type"

        $TestCases = @();
        $SnapshotTypes.ForEach{$TestCases += @{SnapshotTypeDesc = $_.snapshot_type_desc }}
    
        It 'Snapshot Type [<SnapshotTypeDesc>] should respect retention policy' -TestCases $TestCases {
            Param($SnapshotTypeDesc)
    
            $sql = "select count(*)
            from sqlwatch_logger_snapshot_header h
            inner join sqlwatch_config_snapshot_type t
                on h.snapshot_type_id = t.snapshot_type_id
            where datediff(day,h.snapshot_time,getutcdate()) > snapshot_retention_days
            and snapshot_type_desc = '$($SnapshotTypeDesc)'
            and snapshot_retention_days > 0"
    
            $result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql
            $result.Column1 | Should -Be 0 -Because "There should not be any rows beyond the max age."
        }

    }

    Context 'Checking Last Seen Retention Policy is being applied' {

        $sql = "select TABLE_SCHEMA + '.' + TABLE_NAME
        from INFORMATION_SCHEMA.TABLES
        where TABLE_NAME IN (
            select DISTINCT TABLE_NAME
            from INFORMATION_SCHEMA.COLUMNS
            where COLUMN_NAME = 'date_last_seen'
        )
        and TABLE_TYPE = 'BASE TABLE'";
    
        $Tables = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql
    
        $TestCases = @();
        $Tables.ForEach{$TestCases += @{TableName = $_.Column1 }}

        It 'The "Last Seen" Retention in Table [<TableName>] should respect the configuration setting' -TestCases $TestCases {

            Param($TableName)
            
            $sql = "select count(*) from $($TableName) where datediff(day,date_last_seen,getutcdate()) > [dbo].[ufn_sqlwatch_get_config_value](2,null)"
            $result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql
            $result.Column1 | Should -Be 0 -Because "There should not be any rows beyond the max age." 
        }
    }
}

Describe 'Application Errors' {

    Context 'Check Application log for WARNINGS' {

        <# Warnings are OK. Flapping checks or exceeding email thresholds etc.
        It 'Application Log should not contain WARNINGS' {

            $sql = "select count(*) from [dbo].[sqlwatch_app_log]
            where process_message_type = 'WARNING'
            and event_sequence > dateadd(hour,-$($LookBackHours),getutcdate())"

            $result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql
            $result.Column1 | Should -Be 0

        }
        #>
        
        It 'Application Log should not contain ERRORS' {

            $sql = "select count(*) from [dbo].[sqlwatch_app_log]
            where process_message_type = 'ERRROR'
            and event_sequence > dateadd(hour,-$($LookBackHours),getutcdate())"

            $result = Invoke-SqlCmd -ServerInstance $SqlInstance -Database $SqlWatchDatabase -Query $sql
            $result.Column1 | Should -Be 0

        }

    }
}
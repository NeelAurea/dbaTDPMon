-- ============================================================================
-- Copyright (c) 2004-2015 Dan Andrei STEFAN (danandrei.stefan@gmail.com)
-- ============================================================================
-- Author			 : Dan Andrei STEFAN
-- Create date		 : 05.12.2014
-- Module			 : Database Analysis & Performance Monitoring
-- ============================================================================

-----------------------------------------------------------------------------------------------------
--
-----------------------------------------------------------------------------------------------------
RAISERROR('Create table: [dbo].[appConfigurations]', 10, 1) WITH NOWAIT
GO
IF  EXISTS (SELECT * FROM sysobjects WHERE id = OBJECT_ID(N'[dbo].[appConfigurations]') AND type in (N'U'))
DROP TABLE [dbo].[appConfigurations]
GO
CREATE TABLE [dbo].[appConfigurations]
(
	[id]			[smallint] IDENTITY (1, 1)NOT NULL,
	[module]		[varchar](32)			NOT NULL,
	[name] 			[nvarchar](128)			NOT NULL,
	[value]			[nvarchar](128)			NULL,
	CONSTRAINT [PK_appConfigurations] PRIMARY KEY  CLUSTERED 
	(
		[id]
	) ON [PRIMARY],
	CONSTRAINT [UK_appConfigurations_Name] UNIQUE  NONCLUSTERED 
	(
		[module], 
		[name]
	) ON [PRIMARY]
) ON [PRIMARY]
GO

-----------------------------------------------------------------------------------------------------
RAISERROR('		...insert default data', 10, 1) WITH NOWAIT
GO
SET NOCOUNT ON
GO
INSERT	INTO [dbo].[appConfigurations] ([module], [name], [value])
		  SELECT 'common'			AS [module], 'Application Version'															AS [name], N'2016.01.13'AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Default project code'															AS [name], NULL			AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Database Mail profile name to use for sending emails'							AS [name], NULL			AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Default recipients list - Reports (semicolon separated)'						AS [name], NULL			AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Default recipients list - Job Status (semicolon separated)'					AS [name], NULL			AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Default recipients list - Alerts (semicolon separated)'						AS [name], NULL			AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Local storage path for HTML reports'											AS [name], NULL			AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'HTTP address for report files'												AS [name], NULL			AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Alert repeat interval (minutes)'												AS [name], '60'			AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Notify job status only for Failed jobs'										AS [name], 'true'		AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Ignore alerts for: Error 1222 - Lock request time out period exceeded'		AS [name], 'true'		AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Log action events'															AS [name], 'true'		AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Log events retention (days)'													AS [name], '15'			AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Default lock timeout (ms)'													AS [name], '5000'		AS [value]		UNION ALL

		  SELECT 'maintenance-plan' AS [module], 'Default backup location'														AS [name], NULL			AS [value]		UNION ALL
		  SELECT 'maintenance-plan' AS [module], 'Default backup retention (days)'												AS [name], '7'			AS [value]		UNION ALL
		  SELECT 'maintenance-plan' AS [module], 'Change retention policy from RetentionDays to RetentionBackupsCount'			AS [name], 'true'		AS [value]		UNION ALL
		  SELECT 'maintenance-plan' AS [module], 'Force cleanup of ghost records'												AS [name], 'false'		AS [value]		UNION ALL
		  SELECT 'maintenance-plan' AS [module], 'Ghost records cleanup threshold'												AS [name], '131072'		AS [value]		UNION ALL

		  SELECT 'health-check'		AS [module], 'Collect SQL Agent jobs step details'											AS [name], 'false'		AS [value]		UNION ALL
		  SELECT 'health-check'		AS [module], 'Collect SQL Errorlog last files'												AS [name], '1'			AS [value]		UNION ALL
		  SELECT 'health-check'		AS [module], 'Collect Warning OS Events'													AS [name], 'false'		AS [value]		UNION ALL
		  SELECT 'health-check'		AS [module], 'Collect Information OS Events'												AS [name], 'false'		AS [value]		UNION ALL
		  SELECT 'health-check'		AS [module], 'Collect OS Events timeout (seconds)'											AS [name], '600'		AS [value]		UNION ALL
		  SELECT 'health-check'		AS [module], 'Collect OS Events from last hours'											AS [name], '24'			AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Parallel Data Collecting Jobs'												AS [name], '16'			AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Maximum number of retries at failed job'										AS [name], '3'			AS [value]		UNION ALL
		  SELECT 'common'			AS [module], 'Fail master job if any queued job fails'										AS [name], 'false'		AS [value]
GO

---------------------------------------------------------------------------------------------
--get SQL Server running major version
---------------------------------------------------------------------------------------------
DECLARE @SQLMajorVersion [int]
SELECT @SQLMajorVersion = REPLACE(LEFT(ISNULL(CAST(SERVERPROPERTY('ProductVersion') AS [varchar](32)), ''), 2), '.', '') 

DECLARE @queryToRun [nvarchar](1024)

IF @SQLMajorVersion>8
	begin
		SET @queryToRun=N'UPDATE [dbo].[appConfigurations] SET [value]=(select top 1 [name] from msdb.dbo.sysmail_profile) WHERE [name]=''Database Mail profile name to use for sending emails'''
		EXEC (@queryToRun)
	end
GO


---------------------------------------------------------------------------------------------
--get SQL Server instance default backup location
---------------------------------------------------------------------------------------------
DECLARE @defaultBackupDirectory [nvarchar](260)

EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'Software\Microsoft\MSSQLServer\MSSQLServer',
									N'BackupDirectory',
									@defaultBackupDirectory OUTPUT, 
									'no_output'

IF @defaultBackupDirectory IS NOT NULL
	UPDATE [dbo].[appConfigurations] SET [value] = @defaultBackupDirectory WHERE [module] = 'maintenance-plan' AND [name] = 'Default backup location'
GO


---------------------------------------------------------------------------------------------
--enable Parallel Data Collecting Jobs
---------------------------------------------------------------------------------------------
UPDATE [dbo].[appConfigurations] 
	SET [value]= CASE WHEN 4 * (SELECT [cpu_count] FROM sys.dm_os_sys_info)  > 32 
						THEN 32
						ELSE 4 * (SELECT [cpu_count] FROM sys.dm_os_sys_info)
				END
WHERE [module] = 'common' AND [name] = 'Parallel Data Collecting Jobs'
GO

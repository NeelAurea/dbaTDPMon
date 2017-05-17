RAISERROR('Create procedure: [dbo].[usp_mpCheckIndexOnlineOperation]', 10, 1) WITH NOWAIT
GO
IF  EXISTS (
	    SELECT * 
	      FROM sys.objects 
	     WHERE object_id = OBJECT_ID(N'[dbo].[usp_mpCheckIndexOnlineOperation]') 
	       AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[usp_mpCheckIndexOnlineOperation]
GO

-----------------------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_mpCheckIndexOnlineOperation]
		@sqlServerName		[sysname],
		@dbName				[sysname],
		@tableSchema		[sysname]= 'dbo',
		@tableName			[sysname],
		@indexName			[sysname],
		@indexID			[int],
		@partitionNumber	[int] = 1,
		@sqlScriptOnline	[nvarchar](512) OUTPUT,
		@flgOptions			[int] = 0,
		@executionLevel		[tinyint] = 0,
		@debugMode			[bit] = 0
/* WITH ENCRYPTION */
AS

-- ============================================================================
-- Copyright (c) 2004-2015 Dan Andrei STEFAN (danandrei.stefan@gmail.com)
-- ============================================================================
-- Author			 : Dan Andrei STEFAN
-- Create date		 : 24.01.2015
-- Module			 : Database Maintenance Scripts
--					 : SQL Server 2005/2008/2008R2/2012+
-- ============================================================================

-----------------------------------------------------------------------------------------
-- Input Parameters:
--		@flgOptions		 4096  - rebuild/reorganize indexes using ONLINE=ON, if applicable (default)
-----------------------------------------------------------------------------------------

SET NOCOUNT ON

DECLARE	  @queryToRun    			[nvarchar](max)

DECLARE	  @serverEdition			[sysname]
		, @serverVersionStr			[sysname]
		, @serverVersionNum			[numeric](9,6)

DECLARE @onlineConstraintCheck TABLE	
	(
		[value]			[sysname]	NULL
	)


SET @sqlScriptOnline = N''

-----------------------------------------------------------------------------------------
IF @flgOptions & 4096 = 0
	begin
		SET @sqlScriptOnline = N'ONLINE = OFF'
		RETURN
	end

-----------------------------------------------------------------------------------------
/* check if SQL Server Edition is either Enterprise of Developer */
-----------------------------------------------------------------------------------------
--get destination server running version/edition
EXEC [dbo].[usp_getSQLServerVersion]	@sqlServerName			= @sqlServerName,
										@serverEdition			= @serverEdition OUT,
										@serverVersionStr		= @serverVersionStr OUT,
										@serverVersionNum		= @serverVersionNum OUT,
										@executionLevel			= 1,
										@debugMode				= @debugMode

IF NOT (CHARINDEX('Enterprise', @serverEdition) > 0 OR CHARINDEX('Developer', @serverEdition) > 0)
	begin
		SET @sqlScriptOnline = N'ONLINE = OFF'
		RETURN
	end

-----------------------------------------------------------------------------------------
/* check if index can be rebuild online (exceptions listed under https://msdn.microsoft.com/en-us/library/ms188388(v=sql.90).aspx) */
-----------------------------------------------------------------------------------------
IF (@partitionNumber <> 1)
	begin
		SET @sqlScriptOnline = N'ONLINE = OFF'
		RETURN
	end

-----------------------------------------------------------------------------------------
/* disabled indexes / XML, spatial indexes, columnstore, hash */
-----------------------------------------------------------------------------------------
SET @queryToRun = N''
SET @queryToRun = @queryToRun + N'SELECT DISTINCT idx.[name]
						FROM [' + @dbName + '].[sys].[indexes] idx
						INNER JOIN [' + @dbName + '].[sys].[objects]		 obj	ON  idx.[object_id] = obj.[object_id]
						INNER JOIN [' + @dbName + '].[sys].[schemas]		 sch	ON	sch.[schema_id] = obj.[schema_id]
						WHERE	obj.[name] = ''' + @tableName + '''
								AND sch.[name] = ''' + @tableSchema + '''' + 
								CASE	WHEN @indexName IS NOT NULL 
										THEN ' AND idx.[name] = ''' + @indexName	 + ''''
										ELSE ' AND idx.[index_id] = ' + CAST(@indexID AS [nvarchar])
								END + N'
								AND (   idx.[is_disabled] = 1
										OR idx.[type] IN (3, 4, 5, 6, 7)
									)'

SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0

DELETE FROM @onlineConstraintCheck
INSERT	INTO @onlineConstraintCheck([value])
		EXEC (@queryToRun)

IF (SELECT COUNT(*) FROM @onlineConstraintCheck) > 0
	begin
		SET @sqlScriptOnline = N'ONLINE = OFF'
		RETURN
	end

-----------------------------------------------------------------------------------------
/* check if index definition contains a LOB data type */
-----------------------------------------------------------------------------------------
IF @serverVersionNum < 11
	begin
		SET @queryToRun = N''
		SET @queryToRun = @queryToRun + N'SELECT DISTINCT idx.[name]
								FROM [' + @dbName + '].[sys].[indexes] idx
								INNER JOIN [' + @dbName + '].[sys].[index_columns] idxCol ON	idx.[object_id] = idxCol.[object_id]
																								AND idx.[index_id] = idxCol.[index_id]
								INNER JOIN [' + @dbName + '].[sys].[columns]		 col	ON	idxCol.[object_id] = col.[object_id]
																								AND idxCol.[column_id] = col.[column_id]
								INNER JOIN [' + @dbName + '].[sys].[objects]		 obj	ON  idx.[object_id] = obj.[object_id]
								INNER JOIN [' + @dbName + '].[sys].[schemas]		 sch	ON	sch.[schema_id] = obj.[schema_id]
								INNER JOIN [' + @dbName + '].[sys].[types]			 st		ON  col.[system_type_id] = st.[system_type_id]
								WHERE	obj.[name] = ''' + @tableName + '''
										AND sch.[name] = ''' + @tableSchema + '''' + 
										CASE	WHEN @indexName IS NOT NULL 
												THEN ' AND idx.[name] = ''' + @indexName + ''''
												ELSE ' AND idx.[index_id] = ' + CAST(@indexID AS [nvarchar])
										END + N'
										AND (    st.[name] IN (''text'', ''ntext'', ''image''' + CASE WHEN @serverVersionNum < 11 THEN N', ''filestream'', ''xml''' ELSE N'' END + N')
												OR (st.[name] IN (''varchar'', ''nvarchar'', ''varbinary'') AND col.[max_length]=-1)
											)'
		SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
		IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0

		DELETE FROM @onlineConstraintCheck
		INSERT	INTO @onlineConstraintCheck([value])
				EXEC (@queryToRun)

		IF (SELECT COUNT(*) FROM @onlineConstraintCheck) > 0
			begin
				SET @sqlScriptOnline = N'ONLINE = OFF'
				RETURN
			end
	end

-----------------------------------------------------------------------------------------
/* check if table definition contains a LOB data type */
-----------------------------------------------------------------------------------------
IF @serverVersionNum < 11
	begin
		IF @indexID IS NULL
			begin
				SET @queryToRun = N''
				SET @queryToRun = @queryToRun + N'SELECT DISTINCT idx.[index_id]
										FROM [' + @dbName + '].[sys].[indexes] idx
										INNER JOIN [' + @dbName + '].[sys].[objects]		 obj	ON  idx.[object_id] = obj.[object_id]
										INNER JOIN [' + @dbName + '].[sys].[schemas]		 sch	ON	sch.[schema_id] = obj.[schema_id]
										WHERE	obj.[name] = ''' + @tableName + '''
												AND sch.[name] = ''' + @tableSchema + '''
												AND idx.[name] = ''' + @indexName + ''''
				SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
				IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0

				DELETE FROM @onlineConstraintCheck
				INSERT	INTO @onlineConstraintCheck([value])
						EXEC (@queryToRun)

				SELECT TOP 1 @indexID = [value] FROM @onlineConstraintCheck
			end

		IF @indexID=1
			begin
				SET @queryToRun = N''
				SET @queryToRun = @queryToRun + N'SELECT DISTINCT obj.[name]
										FROM  [' + @dbName + '].[sys].[objects]				 obj
										INNER JOIN [' + @dbName + '].[sys].[columns]		 col	ON  col.[object_id] = obj.[object_id]
										INNER JOIN [' + @dbName + '].[sys].[schemas]		 sch	ON	sch.[schema_id] = obj.[schema_id]
										INNER JOIN [' + @dbName + '].[sys].[types]			 st		ON  col.[system_type_id] = st.[system_type_id]
										WHERE	obj.[name] = ''' + @tableName + '''
												AND sch.[name] = ''' + @tableSchema + '''
												AND (    st.[name] IN (''text'', ''ntext'', ''image'', ''filestream'', ''xml'')
														OR (st.[name] IN (''varchar'', ''nvarchar'', ''varbinary'') AND col.[max_length]=-1)
													)'
				SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sqlServerName, @queryToRun)
				IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0

				DELETE FROM @onlineConstraintCheck
				INSERT	INTO @onlineConstraintCheck([value])
						EXEC (@queryToRun)

				IF (SELECT COUNT(*) FROM @onlineConstraintCheck) > 0
					begin
						SET @sqlScriptOnline = N'ONLINE = OFF'
						RETURN
					end
			end
	end

SET @sqlScriptOnline = N'ONLINE = ON'

/* rebuild index online with low priority, starting with version 2014: https://docs.microsoft.com/en-us/sql/t-sql/statements/alter-index-transact-sql */
/* rebuild table online with low priority, starting with version 2014: https://docs.microsoft.com/en-us/sql/t-sql/statements/alter-table-transact-sql */
IF (@serverVersionNum > 12)
	begin
		---------------------------------------------------------------------------------------------
		--get configuration values
		DECLARE @waitMaxDuration [int]
		
		SELECT	@waitMaxDuration = [value] 
		FROM	[dbo].[appConfigurations] 
		WHERE	[name] = 'WAIT_AT_LOW_PRIORITY max duration (min)'
				AND [module] = 'maintenance-plan'

		SET @waitMaxDuration = ISNULL(@waitMaxDuration, 1)
		---------------------------------------------------------------------------------------------

		SET @sqlScriptOnline = @sqlScriptOnline + ' (WAIT_AT_LOW_PRIORITY (MAX_DURATION = ' + CAST(@waitMaxDuration AS [nvarchar]) + ' MINUTES, ABORT_AFTER_WAIT = SELF ))'
	end

RETURN
GO

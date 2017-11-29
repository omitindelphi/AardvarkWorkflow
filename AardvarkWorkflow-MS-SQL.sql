/****** Script for SelectTopNRows command from SSMS  ******/
--create database OIMOpenWF
--go
/*
  At some point in future development script to be splitted into separate parts;
  1. Create all Aadvark Workflow objects
  2. Testing using tSQLt
  3. Clearing off all Aadvark objects.

  Currently script creates Aadvark objects , trest them using pre-installed tSQLt framework and deletes them - all in single run

*/

set nocount on;
go

--EXEC sp_configure 'clr enabled', 1;
--RECONFIGURE;

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'owf')
BEGIN
  exec ('create schema owf' );
end;
go

create table owf.wfItemStatus
( ItemStatusId tinyint not null, 
  ItemStatusName varchar(16) not null,
  ItemStatusR integer not null,
  ItemStatusG integer not null,
  ItemStatusB integer not null,
primary key (ItemStatusId)
)
go

insert into owf.wfItemStatus(ItemStatusId, itemStatusName, ItemStatusR, ItemStatusG, ItemStatusB) values (0,'Ready',255,255,1)
insert into owf.wfItemStatus(ItemStatusId, itemStatusName, ItemStatusR, ItemStatusG, ItemStatusB) values (1,'InProgress',0,255,0)
insert into owf.wfItemStatus(ItemStatusId, itemStatusName, ItemStatusR, ItemStatusG, ItemStatusB) values (2,'Completed',177,180,171)
insert into owf.wfItemStatus(ItemStatusId, itemStatusName, ItemStatusR, ItemStatusG, ItemStatusB) values (3,'Rejected',236,8,5)
insert into owf.wfItemStatus(ItemStatusId, itemStatusName, ItemStatusR, ItemStatusG, ItemStatusB) values (4,'OnHold',129,0,255)
insert into owf.wfItemStatus(ItemStatusId, itemStatusName, ItemStatusR, ItemStatusG, ItemStatusB) values (5,'WaitSync',0,0,255)

go

create table owf.wfChart(ChartId integer identity, 
	ChartName varchar(64) not null,
	ChartDescription Text null,
primary key(ChartId))
go

create table owf.wfTask( TaskId integer identity,
	ChartId integer foreign key references owf.wfChart(ChartId) on update cascade on delete cascade,
	TaskName varchar(64) not null,
	TaskDescription Text,
	X integer null,
	Y integer null,
primary key(TaskId))
go
create unique index ix_task_ChartidTaskName on owf.wfTask(ChartId, TaskName);
go


create table owf.wfRoute(RouteId integer identity,
	FromTaskId integer foreign key references owf.wfTask(TaskId) on update cascade on delete cascade,
	ToTaskId integer,  
	ChartId integer,
	RouteCode varchar(64)  default 'Ok'
primary key (RouteId))
go

alter table  owf.wfRoute
add constraint route_NoDuplicates unique (FromTaskId, TotaskId);
go

alter table  owf.wfRoute
add constraint route_NoSingleLoops check (FromTaskId <> ToTaskId);
go

create trigger trg_Route_Chart_iu
on owf.wfRoute  for insert,update
as
  update owf.wfRoute set owf.wfRoute.ChartId = c.ChartID 
  from 
  owf.wfRoute a
   inner join inserted b on a.RouteId = b.RouteId
   inner join owf.wfTask c on c.TaskId = b.FromTaskId

-- find records that cross chart border
  if exists (
   select * 
    from owf.wfTask a
	inner join  inserted b on a.TaskId = b.FromTaskId
	inner join owf.wfTask c on b.ToTaskId = c.TaskId where 
	c.ChartId <> a.ChartId  
  )
  begin
    RaisError('Route cannot cross chart borders',16,1);
	Rollback Transaction;
	Return
  end

go

create trigger owf.trg_Task_ud
on owf.wfTask for delete
as  --enforce cascade update and delete for route targets
	-- we may not worry about updates in taskID, because it is identity field, so this trigger for deletions only
begin
 declare @TaskIdsDeleted table(L tinyint, TaskId integer);
 insert into @TaskIdsDeleted
	select sum(L) as L, TaskId from
	(
	select 1 as L, TaskId from Inserted
	union all
	select 2 as L, TaskId from Deleted
	) aa
	group by TaskId
	having sum(L) = 2 -- short and fast way to substract tables

	if (select count(L) from @TaskIdsDeleted) > 0  -- deleting task as node in graph removes all routes to that task
	begin
	  delete from owf.wfRoute where ToTaskID in (select TaskId from @TaskIdsDeleted );
	  delete from owf.wfRoute where FromTaskId in (select TaskId from @TaskIdsDeleted );
	end

end
go

-- populate data
insert into owf.wfchart( ChartName) values('TestChart')
insert into owf.wfchart( ChartName) values('SecondChart')
go
-- display current data
-------------------------
select * from owf.wfchart
go

insert into owf. wfTask(ChartId, TaskName, X,Y) values(1, 'InTask', 0, 0)
insert into owf.wfTask(ChartId, TaskName, X,Y) values(1, 'Process', 10, 10)
insert into owf.wfTask(ChartId, TaskName, X,Y) values(1, 'Final', 20, 20)
insert into owf.wfTask(ChartId, TaskName, X,Y) values(2, 'InTask', 0, 0)
insert into owf.wfTask(ChartId, TaskName, X,Y) values(2, 'Process', 10, 10)
insert into owf.wfTask(ChartId, TaskName, X,Y) values(2, 'Final', 20, 20)
go

	
create procedure owf.ChartSet(@Chart varchar(64), @Description Text, @ChartID integer out)
as
begin
  
  if NOT exists( select * from wfChart where ChartName = @chart)
  begin
    insert into owf.wfChart (ChartName) values (@Chart)
  end;
  select @ChartID = ChartID from wfChart where ChartName = @chart;

  if isnull( cast(@Description as varchar(256)),'') <> ''
    update owf.wfChart set ChartDescription = @Description where ChartId = @ChartID;
  else
	update owf.wfChart set ChartDescription = null where ChartId = @ChartID;
end;
go

create procedure owf.TaskSet(@Chart varchar(64), @TaskName varchar(64), @Description Text,  @TaskID integer out)
as
begin
  declare @ChartID integer;
  declare @errMsg varchar(256)
  declare @DescriptionWrite varchar(max);
   
  select @ChartID = ChartID from owf.wfChart where ChartName = @Chart;

  if  @ChartId is null
  begin
	set @errMsg = 'Unknown Chart on TaskSet operation <' +@Chart +'>' 
	RaisError(@errMsg,16,1);
	return;
  end;

  select @TaskId = TaskId from owf.wfTask where ChartId = @ChartId and TaskName = @TaskName
  if @TaskId is null
  begin
	insert into wfTask(ChartId, TaskName, TaskDescription, X, Y) values (@ChartId, @TaskName, @DescriptionWrite, 0, 0 ); 
    select @TaskId = TaskId from owf.wfTask where ChartId = @ChartId and TaskName = @TaskName;
  end

  if isnull( cast(@Description as varchar(256)),'') <> ''
    update owf.wfTask set TaskDescription = @Description where TaskId = @TaskId;
  else
	update owf.wfTask set TaskDescription = null where  TaskId = @TaskId;
  
end;
go

create procedure owf.RouteSet(@Chart varchar(64), @TaskNameFrom varchar(64), @TaskNameTo varchar(64), @RouteCode varchar(64), @RouteID integer out)
as
begin
  declare @ChartID integer;
  declare @errMsg varchar(256)
  declare @DescriptionWrite varchar(max);
  declare @TaskIdFrom integer, @TaskIdTo integer;
  set @ErrMsg = ''; 

  select @ChartID = ChartID from owf.wfChart where ChartName = @Chart;

  if  @ChartId is null
  begin
	set @errMsg = 'Unknown Chart on TaskSet operation <' +@Chart +'>' 
	RaisError(@errMsg,16,1);
	return;
  end;

  select @TaskIdFrom = TaskId from owf.wfTask where ChartId = @ChartId and TaskName = @TaskNameFrom;
  select @TaskIdTo = TaskId from owf.wfTask where ChartId = @ChartId and TaskName = @TaskNameTo;
  
   if  @TaskIdFrom is null
  begin
	set @errMsg = 'Unknown Source task for route set <' +@Chart + '.' + @TaskNameFrom +'>' 
	RaisError(@errMsg,16,1);
	return;
  end;

  if  @TaskIdTo is null
  begin
	set @errMsg = 'Unknown Destination task for route set <' +@Chart + '.' + @TaskNameTo +'>' 
	RaisError(@errMsg,16,1);
	return;
  end;

	select @routeId = RouteId from owf.wfRoute where FromTaskId = @TaskIdFrom and ToTaskId = @TaskIdTo;
	if @routeId is null
		insert into owf.wfRoute (FromTaskId, ToTaskId, RouteCode) values(@TaskIdFrom, @TaskIdTo, @RouteCode)
	else
	    update owf.wfRoute set RouteCode = @RouteCode where FromTaskId = @TaskIdFrom and ToTaskId = @TaskIdTo;

	select @routeId = RouteId from owf.wfRoute where FromTaskId = @TaskIdFrom and ToTaskId = @TaskIdTo;
end;
go

create table owf.wfItem( ItemId bigint identity,
    ChartId integer foreign key references owf.wfChart on delete cascade on update cascade,
	ItemName varchar(64),
	CreatedAt datetime default getdate(),
	primary key(ItemId)
	);
go
	create unique index id_Item_id_name on owf.wfItem(ChartId,ItemName);
go
create table owf.wfItemTask( 
	ItemId bigint foreign key references owf.wfItem(ItemId) on delete cascade,
	TaskId integer foreign key references owf.wfTask(TaskId),
	ItemStatusId tinyint foreign key references owf.wfItemStatus(ItemStatusId),
	ModifiedAt datetime default getdate(),
	primary key(ItemId,TaskId)
	)
go

create table owf.wfChartProp( ChartPropId integer identity,
	ChartId integer foreign key references owf.wfChart(ChartId) on delete cascade,
	ChartPropName varchar(64),
	primary key(chartPropId)
	)
go
	create unique index id_chartProp_id_name on owf.wfChartProp(ChartId,ChartPropName);
go

create table owf.wfItemProp(
	ItemId bigint foreign key references owf.wfItem(ItemId) on delete cascade,
	ChartPropId integer foreign key references owf.wfChartProp(ChartPropId),
	ItemPropValue varchar(256),
	ChartId integer foreign key references owf.wfChart(ChartId),
	primary key(ItemId, ChartPropId)
	)
go
create index id_itemProp_Val on owf.wfItemProp(ItemPropValue);
go
create index id_itemProp_ChartItemProp on owf.wfitemProp(ChartId,ItemId,ChartPropId);
go

create trigger owf.trg_Task_i
on owf.wfItemProp for insert
as 
begin
  update owf.wfItemProp 
	set ChartId = c.ChartId
  from  owf.wfItemProp a
	inner join inserted b on a.ItemId = b.ItemId and a.ChartPropId = b.ChartPropId
	inner join owf.wfItem c on a.ItemId = c.ItemId
end
go

create procedure owf.ItemPropagate(@ItemId integer, @TaskId integer,  @Route varchar(64))
as
begin
-- Procedure works only for normal put operations, when item status set to Complete (2), and there are outgoing routes from the task
   declare @Routes table (TaskId integer, ItemId integer, ItemStatusId tinyint, ItemTaskExists tinyint, primary key(TaskId,ItemId));

            insert into @Routes(TaskId, ItemId, ItemStatusId, ItemTaskExists)
			select c.TaskId, @ItemId as ItemId, cast(0 as tinyint) as ItemStatusId, sign(d.TaskId) as ItemTaskExists from 
				owf.wfRoute a 
					inner join
				owf.wfTask b on b.TaskId = a.FromTaskId and b.TaskId = @TaskId 
					inner join
				owf.wfTask c on c.TaskId = a.ToTaskId 
				    inner join
                owf.wfItemTask e on e.TaskId = b.TaskId and e.ItemId = @ItemId and e.ItemStatusId = 2
				    left outer join
				owf.wfItemTask d on d.TaskId=c.TaskId and d.ItemId=@ItemId
			where a.RouteCode = @Route;

   update owf.wfItemTask set ItemStatusId = 0 
   from owf.wfItemTask
	inner join @Routes a on (owf.wfItemTask.ItemId = a.ItemId and owf.wfItemTask.TaskId =  a.TaskId)
	where a.ItemTaskExists = 1;

	insert into owf.wfItemtask(TaskId, ItemId, ItemstatusId)
	select TaskId, ItemId, 0 as ItemStatusId 
	from @Routes a
	where a.ItemTaskExists is null
end
go

create procedure owf.ItemSet(@Chart varchar(64), @ItemName varchar(64), @TaskName varchar(64), @ItemStatus int, @Route varchar(64))
as 
begin
    declare @ErrMsg varchar(256);
	declare @IncomingRouteCount integer;
    declare @OutgoingRouteCount integer;
	declare @ChartId integer;
	declare @ItemId integer;
	declare @TaskId integer;

	select @ChartId = chartId from owf.wfChart where ChartName = @Chart;
	if @ChartId is null 
	begin
		set @ErrMsg = 'ItemSet error - missing Chart <' + @Chart + '>';
		Raiserror( @ErrMsg, 16, 1);
		return;
	end;

	if @Route is null
		set @Route = 'Ok';


  if NOT exists (select * from owf.wfChart a inner join owf.wfTask b on b.ChartId = a.ChartId )
  begin
    set @ErrMsg = 'ItemSet error - missing task <' + @Chart +'.' + @TaskName + '>';
	Raiserror( @ErrMsg, 16, 1);
	return;
  end;   

    select @TaskId = TaskId from owf.wfTask where TaskName = @TaskName and ChartId = @ChartId;

	select @incomingRouteCount = count(a.RouteId) from 
		owf.wfRoute a 
			inner join
		owf.wfTask b on b.TaskId = a.ToTaskId and b.TaskName = @TaskName
			inner join
		owf.wfChart c on c.ChartName = @Chart and b.ChartId = c.ChartId

	select @OutgoingRouteCount = count(a.RouteId) from 
		owf.wfRoute a 
			inner join
		owf.wfTask b on b.TaskId = a.FromTaskId and b.TaskName = @TaskName
			inner join
		owf.wfChart c on c.ChartName = @Chart and b.ChartId = c.ChartId
	where a.RouteCode = @Route

-- check for tasks without incoming routes - insert item
	if @incomingRouteCount = 0 
	begin
		--if @ItemStatus in (0,1,2)
		--	set @ItemStatus = 2;
        if @ItemStatus in  (1,4,5) 
		begin
			set @ErrMsg = 'ItemSet error - wrong item status for Item insert - must  be 0 [Ready] or 2 [Completed] or 3 [Rejected] ' + @Chart +'.' + @TaskName + '-' + @ItemName  ;
			Raiserror( @ErrMsg, 16, 1);
			return;
		end;
	    if not exists( select * from owf.wfItem where ChartId = @ChartId and ItemName = @ItemName)
			insert into owf.wfItem(ChartId, ItemName) values (@ChartId, @ItemName);
		select @ItemId = a.ItemId from owf.wfItem a where a.ChartId = @ChartId and a.ItemName = @ItemName

		if exists(select * from owf.wfItemTask where ItemId = @ItemId and TaskId = @TaskId) 
			update owf.wfItemTask set ItemStatusId = @ItemStatus where ItemId = @ItemId and TaskId = @TaskId
		else
            insert into owf.wfItemTask(ItemId, TaskId, ItemStatusId) values (@ItemId, @TaskId, @ItemStatus);

        if @OutgoingRouteCount > 0 and @ItemStatus = 2
		begin
		-- if item insert in Completed status, it will be set Ready on outgoing tasks
		    exec owf.ItemPropagate @ItemId, @TaskId,  @Route 
			
		end;
	end;
end;

go
exec [tSQLt].[NewTestClass] 'WFTest';
go

create procedure [WFTest].[Test-01-ExistingChartUpdate]
as
begin

  declare @NewChartId integer;
  declare @ChartName varchar(64);
  set @ChartName = 'TestChart';

  DECLARE @err NVARCHAR(MAX); SET @err = '<No Exception Thrown!>';
  BEGIN TRY
	  exec owf.ChartSet  @ChartName, 'Description Of Test Chart', @NewChartId 
  END TRY
  BEGIN CATCH
    SET @err = ERROR_MESSAGE();
  END CATCH
  
  --        If no exception happened the value of @err is still '<No Exception Thrown>'.

  IF (@err LIKE '%<No Exception Thrown!>%')
  BEGIN
    EXEC tSQLt.ExpectNoException;
  END
  else
  begin
      EXEC tSQLt.Fail 'Unexpected exception thrown. :',@err;
  end;
end;

go

go
create procedure [WFTest].[Test-02-ExistingChartDescriptionUpdate]
as
begin

  declare @NewChartId integer;
  declare @ChartName varchar(64);
  set @ChartName = 'TestChart';
  declare @ActualDesc varchar(256);
  declare @expectedDesc varchar(256);
  set @ExpectedDesc = null;
  

  exec owf.ChartSet  @ChartName, '', @NewChartId 

  select @actualDesc = isnull(cast(a.ChartDescription as varchar(256)), 'AAA') from owf.wfChart a where a.ChartName = @ChartName;

  --        If no exception happened the value of @err is still '<No Exception Thrown>'.
  exec tsqlt.AssertEquals 'AAA', @actualDesc, 'Description of chart is not null on description clearing';

  exec owf.ChartSet  @ChartName, 'ZZZ', @NewChartId 

  select @actualDesc = isnull(cast(a.ChartDescription as varchar(256)), 'AAA') from owf.wfChart a where a.ChartName = @ChartName;
  
  exec tsqlt.AssertEquals 'ZZZ', @actualDesc, 'Description of chart is not null on description clearing';

end;
go

create procedure [WFTest].[Test-03-insertTasksAndDescriptions]
as
begin
  declare @TaskID integer ;
  declare @expected integer;
  declare @ExpectedDescription varchar(256)
  declare @TaskName varchar(64) = 'DelTask';
  
  select @expected = max(TaskId) + 1 from owf.wfTask;

  exec owf.TaskSet 'TestChart', @TaskName, 'YYYYYY',  @TaskID out;

  exec tsqlt.AssertEquals @TaskID, @expected, 'Unexpected taskID to be inserted';
  
  select @ExpectedDescription = cast(TaskDescription as varchar(256)) from owf.wftask where TaskId = @TaskId

  exec tsqlt.AssertEquals @ExpectedDescription, 'YYYYYY', 'Unexpected TaskDescription to be inserted';

  exec owf.TaskSet 'TestChart', @TaskName, '',  @TaskID out;

  select @ExpectedDescription = cast(TaskDescription as varchar(256)) from owf.wftask where TaskId = @TaskId
  select @ExpectedDescription = isnull(@ExpectedDescription, 'ZZZ');
  exec tsqlt.AssertEquals @ExpectedDescription,'ZZZ' , 'TaskDescription failed to be null';

end
go

create procedure [WFTest].[Test-04-insertCrosschartRouteException]
as
begin
  declare @minChart integer;
  declare @maxChart integer;
  declare @FromTask integer;
  declare @ToTask integer;

  select @minChart = min(ChartId), @maxChart = max(ChartId) from owf.wfChart;
  select @FromTask = min(TaskId) from owf.wfTask where ChartId = @minChart;
  select @ToTask = max(TaskId) from owf.wfTask where ChartId = @maxChart;

  select * from owf.wfTask;

  exec tSQLt.ExpectException @ExpectedMessagePattern = '%Route cannot cross chart borders%', @ExpectedSeverity = NULL, @ExpectedState = NULL;
  insert into owf.wfRoute(FromTaskId, TotaskId, RouteCode) values(@FromTask, @ToTask, 'Ok');

end
go

create procedure [WFTest].[Test-05-insertRoutesOk]
as
begin
  declare @routeId integer;
  declare @ActualRouteId integer;
  declare @routeCount integer;

  Exec owf.RouteSet 'TestChart','InTask','Process','Ok', @RouteId out ;
  select @actualRouteId = isnull(max(RouteId), -1) from owf.wfRoute;

  select @Routecount = count(RouteId) from owf.wfRoute;
  exec tsqlt.AssertEquals @Routecount, 1, 'Unexpected number of routes';

  exec tsqlt.AssertEquals @RouteId, @ActualRouteId, 'RouteID unexpected or null'
end
go

/*
create procedure [WFTest].SetUp
as 
begin
  declare @routeId integer;

  --delete from owf.wfRoute;

  Exec owf.RouteSet 'TestChart','InTask','Process','Ok', @RouteId out ;
  Exec owf.RouteSet 'TestChart','Process','Final','Ok', @RouteId out ;
  Exec owf.RouteSet 'SecondChart','InTask','Process','Ok', @RouteId out ;
  Exec owf.RouteSet 'SecondChart','Process','Final','Ok', @RouteId out ;

end
go
*/

create procedure [WFTest].[Test-06-DeleteTasksWithRoutes]
as
begin
  declare @routeId integer;
  declare @ActualRoutes integer;
  declare @routeCount integer;


  insert into owf.wfRoute(FromTaskId, toTaskId) values(1,2);
  insert into owf.wfRoute(FromTaskId, toTaskId) values(2,3);
  insert into owf.wfRoute(FromTaskId, toTaskId) values(4,5);
  insert into owf.wfRoute(FromTaskId, toTaskId) values(5,6);


  delete from owf.wfTask where TaskId = 2;
  delete from owf.wfTask where TaskId = 5;

  select @actualRoutes = count(RouteId) from owf.wfRoute;

  exec tsqlt.AssertEquals @ActualRoutes, 0, 'Presence of unexpected routes after deletion of related nodes';

end
go


create procedure [WFTest].[Test-07-Put-To-TaskNoRoutes-Item-Insertion-On-Isolated-Task-Success]
as
begin
-- should succeed when inserting item in Ready or Rejected or OnHold state and fail in all the other states
  declare @TaskIdIsolated integer;
  declare @ActualRoutes integer;
  declare @ItemCount integer;
  declare @ItemTaskCount integer;


  insert into owf.wfRoute(FromTaskId, toTaskId) values(1,2);
  insert into owf.wfRoute(FromTaskId, toTaskId) values(2,3);
  insert into owf.wfRoute(FromTaskId, toTaskId) values(4,5);
  insert into owf.wfRoute(FromTaskId, toTaskId) values(5,6);


  delete from owf.wfTask where TaskId = 2;
  delete from owf.wfTask where TaskId = 5;

  select @actualRoutes = count(RouteId) from owf.wfRoute;

   exec owf.TaskSet 'TestChart', 'IsolatedTask', 'Entry point (isolated) for inserting items',  @TaskIdIsolated out
   select @TaskIdIsolated = isnull(@TaskIdIsolated, -1)
   exec tsqlt.AssertNotEquals @TaskIdIsolated, -1, 'Task Insertion of Isolated task Failed';

/*   
0,'Ready'
1,'InProgress'
2,'Completed'
3,'Rejected'
4,'OnHold'
5,'WaitSync'
*/

   exec owf.ItemSet 'TestChart', 'A000Ready', 'IsolatedTask', 0, null

   select @ItemTaskCount = count(a.ItemStatusId) from owf.wfItemTask a inner join owf.wfItem b on a.itemId = b.itemId inner join owf.wfChart c on c.ChartId = b.ChartId
   where b.ItemName = 'A000Ready' and c.chartName =  'TestChart' and a.ItemStatusId = 0

   exec tsqlt.AssertEquals 1, @ItemTaskCount, 'ItemTask Status assignment for Insertion on Isolated task as Ready Failed';

   exec owf.ItemSet 'TestChart', 'A000Completed', 'IsolatedTask', 2, null

   select @ItemTaskCount = count(a.ItemStatusId) from owf.wfItemTask a inner join owf.wfItem b on a.itemId = b.itemId inner join owf.wfChart c on c.ChartId = b.ChartId
   where b.ItemName = 'A000Completed' and c.chartName =  'TestChart' and a.ItemStatusId = 2

   exec tsqlt.AssertEquals 1, @ItemTaskCount, 'ItemTask Status assignment for Insertion on Isolated task as Completed Failed';

   exec owf.ItemSet 'TestChart', 'A000Rejected', 'IsolatedTask', 3, null

   select @ItemTaskCount = count(a.ItemStatusId) from owf.wfItemTask a inner join owf.wfItem b on a.itemId = b.itemId inner join owf.wfChart c on c.ChartId = b.ChartId
   where b.ItemName = 'A000Rejected' and c.chartName =  'TestChart' and a.ItemStatusId = 3

   exec tsqlt.AssertEquals 1, @ItemTaskCount, 'ItemTask Status assignment for Insertion on Isolated task as Completed Failed';

end
go

create procedure [WFTest].[Test-08-Put-To-TaskNoRoutes-Item-Insertion-On-Isolated-Task-As-Active-Failure]
as
begin
	exec tSQLt.ExpectException @ExpectedMessage = 'ItemSet error - wrong item status for Item insert - must  be 0 [Ready] or 2 [Completed] or 3 [Rejected] TestChart.IsolatedTask-A000Active', @ExpectedSeverity = null, @ExpectedState = null
	exec owf.ItemSet 'TestChart', 'A000Active', 'IsolatedTask', 1, null
end;
go

create procedure [WFTest].[Test-09-Put-To-TaskNoRoutes-Item-Insertion-On-Isolated-Task-As-OnHold-Failure]
as
begin
	exec tSQLt.ExpectException @ExpectedMessage = 'ItemSet error - wrong item status for Item insert - must  be 0 [Ready] or 2 [Completed] or 3 [Rejected] TestChart.IsolatedTask-A000OnHold', @ExpectedSeverity = null, @ExpectedState = null
	exec owf.ItemSet 'TestChart', 'A000OnHold', 'IsolatedTask', 4, null
end;
go

create procedure [WFTest].[Test-10-Insert-item-to-task-with-normal-single-exit]
as
begin
  -- we should create all tasks in existing chart, and add route to them
  declare @TaskEntryId  int;
  declare @TaskOutId int;
  declare @RouteId int;
  declare @ChartId int;
  exec owf.TaskSet 'TestChart', 'EntryTask', 'Entry point  for inserting items',  @TaskEntryId out;
  exec owf.TaskSet 'TestChart', 'OutTask', 'Destination point  for inserting items',  @TaskOutId out;
  exec owf.RouteSet 'TestChart', 'EntryTask',  'OutTask',  'Ok', @RouteId out;
  -- control of existing configuration
  --select @TaskEntryId as TaskEntryId, @TaskOutId as TaskOutId, @RouteId as RouteId;
  
  select @TaskEntryId = max(a.TaskId) from owf.wfTask a where a.ChartId = 1 and a.TaskName = 'EntryTask';
  select @TaskOutId = max(a.TaskId) from owf.wfTask a where a.ChartId = 1 and a.TaskName = 'OutTask';

  create table #Expected (TaskId integer, ItemId integer, ItemStatusId integer);
  create table #Actual(TaskId integer, ItemId integer, ItemStatusId integer);

  -- when we insert item in Completed status, it is supposed to be Ready on next task in line, as in normal Put operation
  exec owf.ItemSet 'TestChart', 'A000Completed', 'EntryTask', 2, null;

  insert into #Expected(TaskId, ItemId, ItemStatusId) 
	select @TaskEntryId as TaskId, max(a.ItemId) as ItemId, 2 as ItemStatusId
	from 
	owf.wfItem a 
	where a.ItemName = 'A000Completed'
	union all
	select @TaskOutId as TaskId, max(a.ItemId) as ItemId, 0 as ItemStatusId
	from 
	owf.wfItem a 
	where a.ItemName = 'A000Completed'

  insert into #Actual(TaskId, ItemId, ItemStatusId)
  select a.TaskId, a.ItemId, a.ItemStatusId from owf.wfItemTask a
  inner join
  owf.wfItem b on a.ItemId = b.ItemId and b.ItemName = 'A000Completed' and b.ChartId = 1;

  exec tSQLt.AssertEqualsTable '#Expected', '#Actual', 'Item does not propagate down the only Ok route on insert, being Ready on next connected node'
end;
go

create procedure [WFTest].[Test-11-Insert-item-as-AND-split-to-multiple-routes]
as
begin
  declare @TaskEntryId int;
  declare @RouteId int;
  declare @ItemId int;

  exec owf.TaskSet 'TestChart', 'Process02', 'Split node for AND-split 2',  @TaskEntryId out;
  set @TaskEntryId = null
  exec owf.TaskSet 'TestChart', 'Process03', 'Split node for AND-split 3',  @TaskEntryId out;
  set @TaskEntryId = null
  exec owf.TaskSet 'TestChart', 'Process04', 'Split node for AND-split 4',  @TaskEntryId out;

  select @TaskEntryId = TaskId from owf.wfTask where ChartId = 1 and TaskName = 'Process'
  exec owf.TaskSet 'TestChart', 'Process01', 'Split node for AND-split 1',  @TaskEntryId out;
  update owf.wfTask set TaskName = 'Process01' where TaskName = 'Process' and ChartId = 1

  exec owf.RouteSet 'TestChart', 'InTask',  'Process01',  'OkAlt', @RouteId out;
  set @RouteId = null
  exec owf.RouteSet 'TestChart', 'InTask',  'Process02',  'Ok', @RouteId out;
  set @RouteId = null
  exec owf.RouteSet 'TestChart', 'InTask',  'Process03',  'Ok', @RouteId out;
  set @RouteId = null
  exec owf.RouteSet 'TestChart', 'InTask',  'Process04',  'Ok', @RouteId out;
  set @RouteId = null

  -- insert item into InTask with RouteOk as complete - should propagate to Process02, 03, 04 as Ready, staying as Complete on InTask
   exec owf.ItemSet 'TestChart', 'A000Completed', 'InTask', 2, 'Ok';

   select @ItemId = ItemId from owf.wfItem where ChartId = 1 and ItemName = 'A000Completed'

  create table #Expected (TaskId integer, ItemId integer, ItemStatusId integer);
  create table #Actual(TaskId integer, ItemId integer, ItemStatusId integer);

  insert into #Expected(TaskId,ItemId,ItemStatusId)
  select TaskId, @ItemId as ItemId, 2 from owf.wfTask where ChartId = 1 and TaskName = 'InTask'
  union all
  select TaskId, @ItemId as ItemId, 0 from owf.wfTask where ChartId = 1 and TaskName like 'Process%' and TaskName <> 'Process01'

   insert into #Actual(TaskId, ItemId,ItemStatusId)
   select TaskId, ItemId, ItemStatusId  
   from owf.wfItemTask where ItemId = @ItemId
  
   exec tSQLt.AssertEqualsTable '#Expected', '#Actual', 'Item does not propagate down the multiple Ok route on insert as AND-split , being Ready on all connected nodes'
end
go

EXEC tSQLt.RunAll
go

exec tSQLt.DropClass 'WFTest'
go 

drop procedure owf.ItemSet
go
drop procedure owf.ItemPropagate
go
drop procedure owf.RouteSet
go
drop procedure owf.TaskSet
go
drop procedure owf.ChartSet
go
drop table owf.wfItemProp
go
drop table owf.wfChartProp
go
drop table owf.wfItemTask
go
drop table owf.wfItem
go
drop table owf.wfRoute
go
drop table owf.wfTask
go
drop table owf.wfItemStatus
go
drop table owf.wfChart
go

drop schema owf


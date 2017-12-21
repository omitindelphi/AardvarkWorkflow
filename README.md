Simple open-source SQL implementation of Asynchronous Embedded Workflow Management System, for developers.
Focus is on framework for parallel activity of processes working on Items.

Project considered as means to spread data transformation process into space, onto applications, 
as opposite to spreading data process in time in course of conventional approach.

It is asynchronous system; each item can be processed by task's actor as long as necessary, hours and days. 
It is responcibility of Actor (processing application) to provide traceable feedback and report progress.

Item navigation is done using simple Get(task, item) or Put(task,item,Route) Stored Procedures calls

Building of workflow supposed to be in the same way, via Stored Procedure calls;
Any reporting can be done wia direct queries of tables in question.

Primary enities: Tasks, Items, Routes; all of them united into Charts.
Tasks are served by Actor applications.
Navigation of Items through Tasks performed by calling two Stored procedures:
Get(item, task)  - called by Actor, when Actor is ready to process an Item
Put(Item, route, status) - called by Actor, when Actor completed item processing.

That's it.

Idea is that complex systems should start from something simple, and this system can serve as seedling of something big and complex.
Automated chart creation on the fly, process control, web interface, scheduling, parallel synchronization can be added later, 
in form of specialized database applications or entities.

so far - just database structures, ready to use, in addition with sample Actor applications and sample workflows (in progress)

initial implementation in MS SQL, tested with TSQLt
This file notes feature differences and bugfixes contained between releases. 

### v0.9.0 ###

* Default threadpool size has been changed from 5 to 1. This should only affect people who are using the Election code.
* `ZK::Client::Base#register` delegates to its `event_handler` for convenience (so you can write `zk.register` instead of `zk.event_handler.register`, which always irked me)
* `ZK::Client::Base#event_dispatch_thread?` added to more easily allow users to tell if they're currently in the event thread (and possibly make decisions about the safety of their actions). This is now used by `block_until_node_deleted` in the Unixisms module, and prevents a situation where the user could deadlock event delivery.
* Fixed issue 9, where using a Locker in the main thread would never awaken if the connection was dropped or interrupted. Now a `ZK::Exceptions::InterruptedSession` exception (or mixee) will be thrown to alert the caller that something bad happened.
* `ZK::Find.find` now returns the results in sorted order.
* Added documentation explaining the Pool class, reasons for using it, reasons why you shouldn't (added complexities around watchers and events).
* Began work on an experimental Multiplexed client, that would allow multithreaded clients to more effectively share a single connection by making all requests asynchronous behind the scenes, and using a queue to provide a synchronous (blocking) API. 


# vim:ft=markdown

This file notes feature differences and bugfixes contained between releases.

### v1.9.6 ###

* Fixes from @rickypai for ruby 2.2 (#89)
* Remove dependency on logging gem #90 (h/t: @eric)

### v1.9.5 ###

* Really clear hooks when clear! is called #83 (h/t: Liam Stewart)
* implement `add_auth` method to send credentials to zookeeper #86 (h/t: ajf8)

### v1.9.4 ###

* Forward options to underlying connection #69 (h/t: avalanche123)
* Don't check connection state in Locker#assert! - leads to better retry behavior
* allow specifying session-id
* upgrade logging gem dependency


### v1.9.3 ###

* Fix deadlocks between watchers and reconnecting


### v1.9.2 ###

* Fix re-watching znodes after a lost session #72 (reported by kalantar)


### v1.9.1 ###

* Fix re-rewatching children watchers after the parent znode was deleted #68
* Deal with reopening a closed connection properly #70


### v1.9.0 ###

* Semaphores!
* shared/exclusive lock fixes

### v1.8.0 ###

* Added non-exploderating Locker#assert method (issue #48, h/t: johnbellone)

### v1.7.5 ###

* fix for jruby 1.7 (issue #53)

### v1.7.4 ###

* Narsty bug in Locker (#54)

If a locker is waiting on the lock, and a connection interruption occurs (that doesn't render the session invalid), the waiter will attempt to clean up while the connection is invalid, and not succeed in cleaning up its ephemeral. This patch will recognize that the `@lock_path` was already acquired, and just wait on the current owner (ie. it won't create an erroneous *third* lock node). The reproduction code has been added under `spec/informal/two-locks-enter-three-locks-leave.rb`


### v1.7.3 ###

* bug fix for "Callbacks Hash in EventHandlerSubscription::Base gets longer randomly" (#52)

I'd like to point out that the callbacks hash gets longer *deterministically*, depending on what callbacks get registered. This patch will do further cleanup so as not to leave empty arrays littering the EventHandler.

### v1.7.2 ###

* bug fix for "Ephemeral node for exclusive lock not cleaned up when failure happens during lock acquisition" (#51)

### v1.7.1 ###

* Fixes nasty bug "LockWaitTimeout causes lock to be forever unusable" (#49)

The code path in the case of a LockWaitTimeout would skip the lock node cleanup, so a given lock name would become unusable until the timed-out-locker's session went away. This fixes that case and adds specs.

### v1.7.0 ###

* Added Locker timeout feature for blocking calls. (issue #40)

Previously, when dealing with locks, there were only two options: blocking or non-blocking. In order to come up with a time-limited lock, you had to poll every so often until you acquired the lock. This is, needless to say, both inefficient and doesn't allow for fair acquisition.

A timeout option has been added so that when blocking waiting for a lock, you can specify a deadline by which the lock should have been acquired.

```ruby
zk = ZK.new

locker = zk.locker('lock name')

begin
  locker.lock(:wait => 5.0)   # wait up to 5.0 seconds to acquire the lock
rescue ZK::Exceptions::LockWaitTimeoutError
  $stderr.puts "could not acquire the lock in time"
end
```

Also available when using the convenience `#with_lock` methods

```ruby

zk = ZK.new

begin
  zk.with_lock('lock name', :wait => 5.0) do |lock|
    # do stuff while holding lock
  end
rescue ZK::Exceptions::LockWaitTimeoutError
  $stderr.puts "could not acquire the lock in time"
end

```


### v1.6.4 ###

* Remove unnecessary dependency on backports gem
* Fix for use in resque! A small bug was preventing resque from activating the fork hook.

### v1.6.3 ###

* Retry when lock creation fails due to a NoNode exception

### v1.6.2 ###

* Change state call to reduce the chances of deadlocks

One of the problems I've been seeing is that during some kind of shutdown event, some method will call `closed?` or `connected?` which will acquire a mutex and make a call on the underlying connection at the *exact* moment necessary to cause a deadlock. In order to help prevent this, and building on some changes from 1.5.3, we now treat our cached `@last_cnx_state` as the current state of the connection and don't touch the underlying connection object (except in the case of the java driver, which is safe).

### v1.6.1 ###

* Small fixes for zk-eventmachine compatibilty

### v1.6.0 ###

* Locker cleanup code!

When a session is lost, it's likely that the locker's node name was left behind. so for `zk.locker('foo')` if the session is interrupted, it's very likely that the `/_zklocking/foo` znode has been left behind. A method has been added to allow you to safely clean up these stale znodes:

```ruby
ZK.open('localhost:2181') do |zk|
  ZK::Locker.cleanup(zk)
end
```

Will go through your locker nodes one by one and try to lock and unlock them. If it succeeds, the lock is naturally cleaned up (as part of the normal teardown code), if it doesn't acquire the lock, then no harm, it knows that lock is still in use.

* Added `create('/path', 'data', :or => :set)` which will create a node (and all parent paths) with the given data or set its contents if it already exists. It's intended as a convenience when you just want a node to exist with a particular value.

### v1.5.3 ###

* Fixed reconnect code. There was an occasional race/deadlock condition caused because the reopen call was done on the underlying connection's dispatch thread. Closing the dispatch thread is part of reopen, so this would cause a deadlock in real-world use. Moved the reconnect logic to a separate, single-purpose thread on ZK::Client::Threaded that watches for connection state changes.

* 'private' is not 'protected'. I've been writing ruby for several years now, and apparently I'd forgotten that 'protected' does not work like how it does in java. The visibility of these methods has been corrected, and all specs pass, so I don't expect issues...but please report if this change causes any bugs in user code.


### v1.5.2 ###

* Fix locker cleanup code to avoid a nasty race when a session is lost, see [issue #34](https://github.com/slyphon/zk/issues/34)

* Fix potential deadlock in ForkHook code so the mutex is unlocked in the case of an exception

* Do not hang forever when shutting down and the shutdown thread does not exit (wait 30 seconds).

### v1.5.1 ###

* Added a `:retry_duration` option to client constructor which will allows the user to specify for how long in the case of a connection loss, should an operation wait for the connection to be re-established before retrying the operation. This can be set at a global level and overridden on a per-call basis. The default is to not retry (which may change at a later date). Generally speaking, a timeout of > 30s is probably excessive, and care should be taken because during a connection loss, the server-side state may change without you being aware of it (i.e. events will not be delivered).

* Small fork-hook implementation fix. Previously we were using WeakRefs so that hooks would not prevent an object from being garbage collected. This has been replaced with a finalizer which is more deterministic.

### v1.5.0 ###

Ok, now seriously this time. I think all of the forking issues are done.

* Implemented a 'stop the world' feature to ensure safety when forking. All threads are stopped, but state is preserved. `fork()` can then be called safely, and after fork returns, all threads will be restarted in the parent, and the connection will be torn down and reopened in the child.

* The easiest, and supported, way of doing this is now to call `ZK.install_fork_hook` after requiring zk. This will install an `alias_method_chain` style hook around the `Kernel.fork` method, which handles pausing all clients in the parent, calling fork, then resuming in the parent and reconnecting in the child. If you're using ZK in resque, I *highly* recommend using this approach, as it will give the most consistent results.

* Logging is now off by default, and uses the excellent, can't-recommend-it-enough, [logging](https://github.com/TwP/logging) gem. If you want to tap into the ZK logs, you can assign a stdlib compliant logger to `ZK.logger` and that will be used. Otherwise, you can use the Logging framework's controls. All ZK logs are consolidated under the 'ZK' logger instance.

### v1.4.1 ###

* True fork safety! The `zookeeper` at 1.1.0 is finally fork-safe. You can now use ZK in whatever forking library you want. Just remember to call `#reopen` on your client instance in the child process before attempting any opersations.


### v1.4.0 ###

* Added a new `:ignore` option for convenience when you don't care if an operation fails. In the case of a failure, the method will return nil instead of raising an exception. This option works for `children`, `create`, `delete`, `get`, `get_acl`, `set`, and `set_acl`. `stat` will ignore the option (because it doesn't care about the state of a node).

```
# so instead of having to do:

begin
  zk.delete('/some/path')
rescue ZK::Exceptions;:NoNode
end

# you can do

zk.delete('/some/path', :ignore => :no_node)

```

* MASSIVE fork/parent/child test around event delivery and much greater stability expected for linux (with the zookeeper-1.0.3 gem). Again, please see the documentation on the wiki about [proper fork procedure](http://github.com/slyphon/zk/wiki/Forking).

### v1.3.1 ###

* [fix a bug][bug 1.3.1] where a forked client would not have its 'outstanding watches' cleared, so some events would never be delivered

[bug 1.3.1]: https://github.com/slyphon/zk/compare/release/1.3.0...9f68cee958fdaad8d32b6d042bf0a2c9ab5ec9b0

### v1.3.0 ###

Phusion Passenger and Unicorn users are encouraged to upgrade!

* __fork()__: ZK should now work reliably after a fork() if you call `reopen()` ASAP in the child process (before continuing any ZK work). Additionally, your event-handler (blocks set up with `zk.register`) will still work in the child. You will have to make calls like `zk.stat(path, :watch => true)` to tell ZooKeeper to notify you of events (as the child will have a new session), but everything should work.

* See the fork-handling documentation [on the wiki](http://github.com/slyphon/zk/wiki/Forking).


### v1.2.0 ###

You are __STRONGLY ENCOURAGED__ to go and look at the [CHANGELOG](http://git.io/tPbNBw) from the zookeeper 1.0.0 release

* NOTICE: This release uses the 1.0 release of the zookeeper gem, which has had a MAJOR REFACTORING of its namespaces. Included in that zookeeper release is a compatibility layer that should ease the transition, but any references to Zookeeper\* heirarchy should be changed.

* Refactoring related to the zokeeper gem, use all the new names internally now.

* Create a new Subscription class that will be used as the basis for all subscription-type things.

* Add new Locker features!
  * `LockerBase#assert!` - will raise an exception if the lock is not held. This check is not only for local in-memory "are we locked?" state, but will check the connection state and re-run the algorithmic tests that determine if a given Locker implementation actually has the lock.
  * `LockerBase#acquirable?` - an advisory method that checks if any condition would prevent the receiver from acquiring the lock.

* Deprecation of the `lock!` and `unlock!` methods. These may change to be exception-raising in a future relase, so document and refactor that `lock` and `unlock` are the way to go.

* Fixed a race condition in `event_catcher_spec.rb` that would cause 100% cpu usage and hang.

### v1.1.1 ###

* Documentation for Locker and ilk

* Documentation cleanup

* Fixes for Locker tests so that we can run specs against all supported ruby implementations on travis (relies on in-process zookeeper server in the zk-server-1.0.1 gem)

* Support for 1.8.7 will be continued

## v1.1.0 ##

(forgot to put this here, put it in the readme though)

* NEW! Thread-per-Callback event delivery model! [Read all about it!](https://github.com/slyphon/zk/wiki/EventDeliveryModel). Provides a simple, sane way to increase the concurrency in your ZK-based app while maintaining the ordering guarantees ZooKeeper makes. Each callback can perform whatever work it needs to without blocking other callbacks from receiving events. Inspired by [Celluloid's](https://github.com/celluloid/celluloid) actor model.

* Use the [zk-server](https://github.com/slyphon/zk-server) gem to run a standalone ZooKeeper server for tests (`rake SPAWN_ZOOKEEPER=1`). Makes live-fire testing of any project that uses ZK easy to run anywhere!


### v1.0.0 ###

* Threaded client (the default one) will now automatically reconnect (i.e. `reopen()`) if a `SESSION_EXPIRED` or `AUTH_FAILED` event is received. Thanks to @eric for pointing out the _nose-on-your-face obviousness_ and importance of this. If users want to handle these events themselves, and not automatically reopen, you can pass `:reconnect => false` to the constructor.

* allow for both :sequence and :sequential arguments to create, because I always forget which one is the "right one"

* add zk.register(:all) to recevie node updates for all nodes (i.e. not filtered on path)

* add 'interest' feature to zk.register, now you can indicate what kind of events should be delivered to the given block (previously you had to do that filtering inside the block). The default behavior is still the same, if no 'interest' is given, then all event types for the given path will be delivered to that block.
  
    zk.register('/path', :created) do |event|
      # event.node_created? will always be true
    end

    # or multiple kinds of events

    zk.register('/path', [:created, :changed]) do |event|
      # (event.node_created? or event.node_changed?) will always be true
    end

* create now allows you to pass a path and options, instead of requiring the blank string

    zk.create('/path', '', :sequential => true)

    # now also

    zk.create('/path', :sequential => true)

* fix for shutdown: close! called from threadpool will do the right thing

* Chroot users rejoice! By default, ZK.new will create a chrooted path for you.

    ZK.new('localhost:2181/path', :chroot => :create) # the default, create the path before returning connection

    ZK.new('localhost:2181/path', :chroot => :check)  # make sure the chroot exists, raise if not

    ZK.new('localhost:2181/path', :chroot => :do_nothing) # old default behavior

    # and, just for kicks

    ZK.new('localhost:2181', :chroot => '/path') # equivalent to 'localhost:2181/path', :chroot => :create

* Most of the event functionality used is now in a ZK::Event module. This is still mixed into the underlying slyphon-zookeeper class, but now all of the important and relevant methods are documented, and Event appears as a first-class citizen.

* Support for 1.8.7 WILL BE *DROPPED* in v1.1. You've been warned.

### v0.9.1 ###

The "Don't forget to update the RELEASES file before pushing a new release" release

* Fix a fairly bad bug in event de-duplication (diff: http://is.gd/a1iKNc)

	This is fairly edge-case-y but could bite someone. If you'd set a watch
	when doing a get that failed because the node didn't exist, any subsequent
	attempts to set a watch would fail silently, because the client thought that the
	watch had already been set.

	We now wrap the operation in the setup_watcher! method, which rolls back the
	record-keeping of what watches have already been set for what nodes if an
	exception is raised.

	This change has the side-effect that certain operations (get,stat,exists?,children)
	will block event delivery until completion, because they need to have a consistent
	idea about what events are pending, and which have been delivered. This also means
	that calling these methods represent a synchronization point between user threads
	(these operations can only occur serially, not simultaneously).


### v0.9.0 ###

* Default threadpool size has been changed from 5 to 1. This should only affect people who are using the Election code.
* `ZK::Client::Base#register` delegates to its `event_handler` for convenience (so you can write `zk.register` instead of `zk.event_handler.register`, which always irked me)
* `ZK::Client::Base#event_dispatch_thread?` added to more easily allow users to tell if they're currently in the event thread (and possibly make decisions about the safety of their actions). This is now used by `block_until_node_deleted` in the Unixisms module, and prevents a situation where the user could deadlock event delivery.
* Fixed issue 9, where using a Locker in the main thread would never awaken if the connection was dropped or interrupted. Now a `ZK::Exceptions::InterruptedSession` exception (or mixee) will be thrown to alert the caller that something bad happened.
* `ZK::Find.find` now returns the results in sorted order.
* Added documentation explaining the Pool class, reasons for using it, reasons why you shouldn't (added complexities around watchers and events).
* Began work on an experimental Multiplexed client, that would allow multithreaded clients to more effectively share a single connection by making all requests asynchronous behind the scenes, and using a queue to provide a synchronous (blocking) API.


# vim:ft=markdown:sts=2:sw=2:et

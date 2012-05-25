# ZK #

[![Build Status (master)](https://secure.travis-ci.org/slyphon/zk.png?branch=master)](http://travis-ci.org/slyphon/zk)

ZK is an application programmer's interface to the Apache [ZooKeeper][] server. It is based on the [zookeeper gem][] which is a multi-Ruby low-level driver. Currently MRI 1.8.7, 1.9.2, 1.9.3, REE, and JRuby are supported. Rubinius 2.0.testing is supported-ish (it's expected to work, but upstream is unstable, so YMMV). 

ZK is licensed under the [MIT][] license. 

The key place to start in the documentation is with ZK::Client::Base ([rubydoc.info][ZK::Client::Base], [local](/docs/ZK/Client/Base)).

See the [RELEASES][] file for information on what changed between versions.

This library is heavily used in a production deployment and is actively developed and maintained.

Development is sponsored by [Snapfish][] and has been generously released to the Open Source community by HPDC, L.P.

[ZK::Client::Base]: http://rubydoc.info/gems/zk/ZK/Client/Base
[ZooKeeper]: http://zookeeper.apache.org/ "Apache ZooKeeper"
[zookeeper gem]: https://github.com/slyphon/zookeeper "slyphon-zookeeper gem"
[MIT]: http://www.gnu.org/licenses/license-list.html#Expat "MIT (Expat) License"
[Snapfish]: http://www.snapfish.com/ "Snapfish"
[RELEASES]: https://github.com/slyphon/zk/blob/master/RELEASES.markdown

## What is ZooKeeper? ##

ZooKeeper is a multi-purpose tool that is designed to allow you to write code that coordinates many nodes in a cluster. It can be used as a directory service, a configuration database, and can provide cross-cluster [locking][], [leader election][], and [group membership][] (to name a few). It presents to the user what looks like a distributed file system, with a few important differences: every node can have children _and_ data, and there is a 1MB limit on data size for any given node. ZooKeeper provides atomic semantics and a simple API for manipulating data in the heirarchy.

One of the most useful aspects of ZooKeeper is the ability to set "[watches][]" on nodes. This allows one to be notified when a node has been deleted, created, changd, or has had its list of child znodes modified. The asynchronous nature of these watches enables you to write code that can _react_ to changes in your environment without polling and busy-waiting.

Znodes can be _ephemeral_, which means that when the connection that created them goes away, they're automatically cleaned up, and all the clients that were watching them are notified of the deletion. This is an incredibly useful mechanism for providing _presence_ in a cluster ("which of my thingamabobers are up?). If you've ever run across a stale pid file or lock, you can imagine how useful this feature can be. 

Znodes can also be created as _sequence_ nodes, which means that beneath a given path, a node can be created with a given prefix and assigned a unique integer. This, along with the _ephemeral_ property, provide the basis for most of the coordination classes such as [groups][] and [locks][].

ZooKeeper is easy to deploy in a [Highly Available][ha-config] configuration, and the clients natively understand the clustering and how to resume a session transparently when one of the cluster nodes goes away. 

[watches]: http://zookeeper.apache.org/doc/current/zookeeperProgrammers.html#ch_zkWatches
[locking]: http://zookeeper.apache.org/doc/current/recipes.html#sc_recipes_Locks
[leader election]: http://zookeeper.apache.org/doc/current/recipes.html#sc_leaderElection
[group membership]: http://zookeeper.apache.org/doc/current/recipes.html#sc_outOfTheBox
[ha-config]: http://zookeeper.apache.org/doc/current/zookeeperAdmin.html#sc_CrossMachineRequirements "HA config"
[groups]: https://github.com/slyphon/zk-group
[locks]: http://rubydoc.info/gems/zk/ZK/Locker


## What does ZK do that the zookeeper gem doesn't?

The [zookeeper gem][] provides a low-level, cross platform library for interfacing with ZooKeeper. While it is full featured, it only handles the basic operations that the driver provides. ZK implements the majority of the [recipes][] in the ZooKeeper documentation, plus a number of other conveniences for a production environment. ZK aims to be to Zookeeper, as Sequel or ActiveRecord is to the MySQL or Postgres drivers (not that ZK is attempting to provide an object persistence system, but rather a higher level API that users can develop applications with).

ZK provides:

* 	a robust lock implementation (both shared and exclusive locks)
* 	a leader election implementation with both "leader" and "observer" roles
* 	a higher-level interface to the ZooKeeper callback/watcher mechanism than the [zookeeper gem][] provides
* 	a simple threadpool implementation
* 	a bounded, dynamically-growable (threadsafe) client pool implementation
* 	a recursive Find class (like the Find module in ruby-core)
* 	unix-like rm\_rf and mkdir\_p methods
* 	an extension for the [Mongoid][] ORM to provide advisory locks on mongodb records

In addition to all of that, I would like to think that the public API the ZK::Client provides is more convenient to use for the common (synchronous) case. For use with [EventMachine][] there is [zk-eventmachine][] which provides a convenient API for writing evented code that uses the ZooKeeper server.

[recipes]: http://zookeeper.apache.org/doc/current/recipes.html
[Mongoid]: http://mongoid.org/
[EventMachine]: https://github.com/eventmachine/eventmachine
[zk-eventmachine]: https://github.com/slyphon/zk-eventmachine

## NEWS ##
### v1.6.0 ###

* Locker cleanup code!

When a session is lost, it's likely that the locker's node name was left behind. so for `zk.locker('foo')` if the session is interrupted, it's very likely that the `/_zklocking/foo` znode has been left behind. A method has been added to allow you to safely clean up these stale znodes:

```ruby
ZK.open('localhost:2181') do |zk|
  ZK::Locker.cleanup(zk)
end
```

Will go through your locker nodes one by one and try to lock and unlock them. If it succeeds, the lock is naturally cleaned up (as part of the normal teardown code), if it doesn't acquire the lock, then no harm, it knows that lock is still in use.

### v1.5.3 ###

* Fixed reconnect code. There was an occasional race/deadlock condition caused because the reopen call was done on the underlying connection's dispatch thread. Closing the dispatch thread is part of reopen, so this would cause a deadlock in real-world use. Moved the reconnect logic to a separate, single-purpose thread on ZK::Client::Threaded that watches for connection state changes. 

* 'private' is not 'protected'. I've been writing ruby for several years now, and apparently I'd forgotten that 'protected' does not work like how it does in java. The visibility of these methods has been corrected, and all specs pass, so I don't expect issues...but please report if this change causes any bugs in user code.

### v1.5.2 ###

* Fix locker cleanup code to avoid a nasty race when a session is lost, see [issue #34](https://github.com/slyphon/zk/issues/34)

* Fix potential deadlock in ForkHook code so the mutex is unlocked in the case of an exception

* Do not hang forever when shutting down and the shutdown thread does not exit (wait 30 seconds).

### v1.5.1 ###

* Added a `:retry_duration` option to the Threaded client constructor which will allows the user to specify for how long in the case of a connection loss, should an operation wait for the connection to be re-established before retrying the operation. This can be set at a global level and overridden on a per-call basis. The default is to not retry (which may change at a later date). Generally speaking, a timeout of > 30s is probably excessive, and care should be taken because during a connection loss, the server-side state may change without you being aware of it (i.e. events will not be delivered). 

* Small fork-hook implementation fix. Previously we were using WeakRefs so that hooks would not prevent an object from being garbage collected. This has been replaced with a finalizer which is more deterministic.

### v1.5.0 ###

Ok, now seriously this time. I think all of the forking issues are done. 

* Implemented a 'stop the world' feature to ensure safety when forking. All threads are stopped, but state is preserved. `fork()` can then be called safely, and after fork returns, all threads will be restarted in the parent, and the connection will be torn down and reopened in the child. 

* The easiest, and supported, way of doing this is now to call `ZK.install_fork_hook` after requiring zk. This will install an `alias_method_chain` style hook around the `Kernel.fork` method, which handles pausing all clients in the parent, calling fork, then resuming in the parent and reconnecting in the child. If you're using ZK in resque, I *highly* recommend using this approach, as it will give the most consistent results.

In your app that requires an open ZK instance and `fork()`:

```ruby

require 'zk'
ZK.install_fork_hook

```

Then use fork as you normally would.

* Logging is now off by default, but we now use the excellent, can't-recommend-it-enough, [logging](https://github.com/TwP/logging) gem. If you want to tap into the ZK logs, you can assign a stdlib compliant logger to `ZK.logger` and that will be used. Otherwise, you can use the Logging framework's controls. All ZK logs are consolidated under the 'ZK' logger instance.


### v1.4.1 ###

* All users of resque or other libraries that depend on `fork()` are encouraged to upgrade immediately. This version of ZK features the `zookeeper-1.1.0` gem with a completely rewritten backend that provides true fork safety. The rules still apply (you must call `#reopen` on your client as soon as possible in the child process) but you can be assured a much more stable experience.

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



## Caveats

ZK strives to be a complete, correct, and convenient way of interacting with ZooKeeper. There are a few things to be aware of:

* In versions &lte; 0.9 there is only *one* event dispatch thread. It is *very important* that you don't block the event delivery thread. In 1.0, there is one delivery thread by default, but you can adjust the level of concurrency, allowing more control and convenience for building your event-driven app.

* ZK uses threads. You will have to use synchronization primitives if you want to avoid getting hurt. There are use cases that do not require you to think about this, but as soon as you want to register for events, you're using multiple threads. 

* If you're not familiar with developing solutions with zookeeper, you should read about [sessions][] and [watches][] in the Programmer's Guide. Even if you *are* familiar, you should probably go read it again. 

* It is very important that you not ignore connection state events if you're using watches.

* _ACLS: HOW DO THEY WORK?!_  ACL support is mainly faith-based now. I have not had a need for ACLs, and the authors of the upstream [twitter/zookeeper][] code also don't seem to have much experience with them/use for them (purely my opinion, no offense intended). If you are using ACLs and you find bugs or have suggestions, I would much appreciate feedback or examples of how they *should* work so that support and tests can be added.

* ZK::Client supports asynchronous calls of all basic methods (get, set, delete, etc.) however these versions are kind of inconvenient to use. For a fully evented stack, try [zk-eventmachine][], which is designed to be compatible and convenient to use in event-driven code.

[twitter/zookeeper]: https://github.com/twitter/zookeeper
[async-branch]: https://github.com/slyphon/zk/tree/dev%2Fasync-conveniences
[chroot]: http://zookeeper.apache.org/doc/current/zookeeperProgrammers.html#ch_zkSessions
[YARD]: http://yardoc.org/
[sessions]: http://zookeeper.apache.org/doc/current/zookeeperProgrammers.html#ch_zkSessions 
[watches]: http://zookeeper.apache.org/doc/r3.3.5/zookeeperProgrammers.html#ch_zkWatches

## Users

* [papertrail](http://papertrailapp.com/): Hosted log management service
* [redis\_failover](https://github.com/ryanlecompte/redis_failover): Redis client/server failover managment system
* [DCell](https://github.com/celluloid/dcell): Distributed ruby objects, built on top of the super cool [Celluloid](https://github.com/celluloid/celluloid) framework.


## Dependencies

* The [slyphon-zookeeper gem][szk-gem] ([repo][szk-repo]).

* For JRuby, the [slyphon-zookeeper\_jar gem][szk-jar-gem] ([repo][szk-jar-repo]), which just wraps the upstream zookeeper driver jar in a gem for easy installation

[szk-gem]: https://rubygems.org/gems/slyphon-zookeeper
[szk-repo]: https://github.com/slyphon/zookeeper
[szk-repo-bundler]: https://github.com/slyphon/zookeeper/tree/dev/gemfile/
[szk-jar-gem]: https://rubygems.org/gems/slyphon-zookeeper_jar
[szk-jar-repo]: https://github.com/slyphon/zookeeper_jar

## Contacting the author

* I'm usually hanging out in IRC on freenode.net in the BRAND NEW #zk-gem channel.
* if you really want to, you can also reach me via twitter [@slyphon][]

[@slyphon]: https://twitter.com/#!/slyphon



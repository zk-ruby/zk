# ZK

ZK is a high-level interface to the Apache [ZooKeeper][] server. It is based on the [zookeeper gem][] which is a multi-Ruby low-level driver. Currently MRI 1.8.7, 1.9.2, 1.9.3, and JRuby are supported, rubinius 2.0.testing is supported-ish (it's expected to work, but upstream is unstable, so YMMV). 

ZK is licensed under the [MIT][] license. 

The key place to start in the documentation is with ZK::Client::Base ([rubydoc.info][ZK::Client::Base], [local](/docs/ZK/Client/Base)).

This library is heavily used in a production deployment and is actively developed and maintained.

Development is sponsored by [Snapfish][] and has been generously released to the Open Source community by HPDC, L.P.

[ZK::Client::Base]: http://rubydoc.info/gems/zk/ZK/Client/Base
[ZooKeeper]: http://zookeeper.apache.org/ "Apache ZooKeeper"
[zookeeper gem]: https://github.com/slyphon/zookeeper "slyphon-zookeeper gem"
[MIT]: http://www.gnu.org/licenses/license-list.html#Expat "MIT (Expat) License"
[Snapfish]: http://www.snapfish.com/ "Snapfish"

## New in 1.1 !! ##

* NEW! Thread-per-Callback event delivery model! [Read all about it!](https://github.com/slyphon/zk/wiki/EventDeliveryModel). Provides a simple, sane way to increase the concurrency in your ZK-based app while maintaining the ordering guarantees ZooKeeper makes. Each callback can perform whatever work it needs to without blocking other callbacks from receiving events. Inspired by [Celluloid's](https://github.com/celluloid/celluloid) actor model.

* Use the [zk-server](https://github.com/slyphon/zk-server) gem to run a standalone ZooKeeper server for tests (`rake SPAWN_ZOOKEEPER=1`). Makes live-fire testing of any project that uses ZK easy to run anywhere!

## New in 1.0 ##

* Threaded client (the default one) will now automatically reconnect (i.e. `reopen()`) if a `SESSION_EXPIRED` or `AUTH_FAILED` event is received. Thanks to @eric for pointing out the _nose-on-your-face obviousness_ and importance of this. If users want to handle these events themselves, and not automatically reopen, you can pass `:reconnect => false` to the constructor.

* allow for both :sequence and :sequential arguments to create, because I always forget which one is the "right one"

* add zk.register(:all) to recevie node updates for all nodes (i.e. not filtered on path)

* add 'interest' feature to zk.register, now you can indicate what kind of events should be delivered to the given block (previously you had to do that filtering inside the block). The default behavior is still the same, if no 'interest' is given, then all event types for the given path will be delivered to that block.
  
```ruby
zk.register('/path', :created) do |event|
  # event.node_created? will always be true
end

# or multiple kinds of events

zk.register('/path', [:created, :changed]) do |event|
  # (event.node_created? or event.node_changed?) will always be true
end

# this will, however, be changed in 1.1 to (backwards compatible, with a deprecation warning)

zk.register('/path', :only => :created) do |event|
end

```

* create now allows you to pass a path and options, instead of requiring the blank string

```ruby
zk.create('/path', '', :sequential => true)

# now also

zk.create('/path', :sequential => true)
```

* fix for shutdown: close! called from threadpool will do the right thing

* Chroot users rejoice! By default, ZK.new will create a chrooted path for you. 
    
```ruby
ZK.new('localhost:2181/path', :chroot => :create) # the default, create the path before returning connection

ZK.new('localhost:2181/path', :chroot => :check)  # make sure the chroot exists, raise if not

ZK.new('localhost:2181/path', :chroot => :do_nothing) # old default behavior

# and, just for kicks

ZK.new('localhost:2181', :chroot => '/path') # equivalent to 'localhost:2181/path', :chroot => :create
```

* Most of the event functionality used is now in a ZK::Event module. This is still mixed into the underlying slyphon-zookeeper class, but now all of the important and relevant methods are documented, and Event appears as a first-class citizen.

* Support for 1.8.7 WILL BE *DROPPED* in v1.1. You've been warned.

## What is ZooKeeper good for?

ZooKeeper is a multi-purpose tool that is designed to allow you to write code that coordinates many nodes in a cluster. It can be used as a directory service, a configuration database, and can provide cross-cluster [locking][], [leader election][], and [group membership][] (to name a few). It presents to the user what looks like a distributed file system, with a few important differences: every node can have children _and_ data, and there is a 1MB limit on data size for any given node. ZooKeeper provides atomic semantics and a simple API for manipulating data in the heirarchy.

One of the most useful aspects of ZooKeeper is the ability to set "[watches][]" on nodes. This allows one to be notified when a node has been deleted, created, has had a child modified, or had its data modified. The asynchronous nature of these watches enables you to write code that can _react_ to changes in your environment.

ZooKeeper is also (relatively) easy to deploy in a [Highly Available][ha-config] configuration, and the clients natively understand the clustering and how to resume a session transparently when one of the cluster nodes goes away. 


[watches]: http://zookeeper.apache.org/doc/current/zookeeperProgrammers.html#ch_zkWatches
[locking]: http://zookeeper.apache.org/doc/current/recipes.html#sc_recipes_Locks
[leader election]: http://zookeeper.apache.org/doc/current/recipes.html#sc_leaderElection
[group membership]: http://zookeeper.apache.org/doc/current/recipes.html#sc_outOfTheBox
[ha-config]: http://zookeeper.apache.org/doc/current/zookeeperAdmin.html#sc_CrossMachineRequirements "HA config"

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

* Send me a github message (slyphon)
* I'm usually hanging out in IRC on freenode.net in #ruby-lang and in #zookeeper
* if you really want to, you can also reach me via twitter [@slyphon][]

[@slyphon]: https://twitter.com/#!/slyphon


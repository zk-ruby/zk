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



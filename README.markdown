# ZK

ZK is a high-level interface to the Apache [ZooKeeper][] server. It is based on the [zookeeper gem][] which is a multi-Ruby low-level driver. Currently MRI 1.8.7, 1.9.2, 1.9.3, and JRuby are supported (rubinius 1.2 is experimental but _should_ work). It is licensed under the [MIT][] license. 

This library is heavily used in a production deployment and is actively developed and maintained.

Development is sponsored by [Snapfish][] and has been generously released to the Open Source community by HPDC, L.P.

[ZooKeeper]: http://zookeeper.apache.org/ "Apache ZooKeeper"
[zookeeper gem]: https://github.com/slyphon/zookeeper "slyphon-zookeeper gem"
[MIT]: http://www.gnu.org/licenses/license-list.html#Expat "MIT (Expat) License"
[Snapfish]: http://www.snapfish.com/ "Snapfish"

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

The [zookeeper gem][] provides a low-level, cross platform library for interfacing with ZooKeeper. While it is full featured, it only handles the basic operations that the driver provides. ZK implements the majority of the [recipes][] in the ZooKeeper documentation, plus a number of other conveniences for a production environment. 

ZK provides:

* 	a robust lock implementation (both shared and exclusive locks)
* 	a leader election implementation with both "leader" and "observer" roles
* 	a higher-level interface to the ZooKeeper callback/watcher mechanism than the [zookeeper gem][] provides
* 	a simple threadpool implementation
* 	a bounded, dynamically-growable (threadsafe) client pool implementation
* 	a recursive Find class (like the Find module in ruby-core)
* 	unix-like rm\_rf and mkdir\_p methods (useful for functional testing)
* 	an extension for the [Mongoid][] ORM to provide advisory locks on mongodb records

In addition to all of that, I would like to think that the public API the ZK::Client provides is more convenient to use for the common (synchronous) case. For use with [EventMachine][] there is [zk-eventmachine][] which provides a convenient API for writing evented code that uses the ZooKeeper server.

[recipes]: http://zookeeper.apache.org/doc/current/recipes.html
[Mongoid]: http://mongoid.org/
[EventMachine]: https://github.com/eventmachine/eventmachine
[zk-eventmachine]: https://github.com/slyphon/zk-eventmachine

## Caveats

ZK strives to be a complete, correct, and convenient way of interacting with ZooKeeper. There are a few weak points in the implementation:

* Starting with 0.9 there is only *one* event dispatch thread (in 0.8 there are 5). It is *very important* that you don't block the event delivery thread.

* If you're not familiar with developing solutions with zookeeper, you should read about [sessions][] and [watches][] in the Programmer's Guide. Even if you *are* familiar, you should probably go read it again. 

* It is very important that you not ignore connection state events if you're using watches.

* _ACLS: HOW DO THEY WORK?!_  ACL support is mainly faith-based now. I have not had a need for ACLs, and the authors of the upstream [twitter/zookeeper][] code also don't seem to have much experience with them/use for them (purely my opinion, no offense intended). If you are using ACLs and you find bugs or have suggestions, I would much appreciate feedback or examples of how they *should* work so that support and tests can be added.

* ZK::Client supports asynchronous calls of all basic methods (get, set, delete, etc.) however these versions are kind of inconvenient to use. For a fully evented stack, try [zk-eventmachine][], which is designed to be compatible and convenient to use in event-driven code.

* ZooKeeper "chroot" [connection syntax][chroot] is currently being developed and should work for most cases. Right now we require that the root path exist before the chrooted client is used, but that may change [in the near future](https://github.com/slyphon/zk/issues/7).

[twitter/zookeeper]: https://github.com/twitter/zookeeper
[async-branch]: https://github.com/slyphon/zk/tree/dev%2Fasync-conveniences
[chroot]: http://zookeeper.apache.org/doc/current/zookeeperProgrammers.html#ch_zkSessions
[YARD]: http://yardoc.org/
[sessions]: http://zookeeper.apache.org/doc/current/zookeeperProgrammers.html#ch_zkSessions 
[watches]: http://zookeeper.apache.org/doc/r3.3.5/zookeeperProgrammers.html#ch_zkWatches

## Dependencies

* The [slyphon-zookeeper gem][szk-gem] ([repo][szk-repo], branch with Gemfile [here][szk-repo-bundler]), which adds JRuby compatibility and a full suite of tests to the excellent [twitter/zookeeper][] project. _(I'm hoping to get this merged upstream, but it's a large change and, you know, people have day jobs)_. 

* For JRuby, the [slyphon-zookeeper\_jar gem][szk-jar-gem] ([repo][szk-jar-repo]), which just wraps the upstream zookeeper driver jar in a gem for easy installation

[szk-gem]: https://rubygems.org/gems/slyphon-zookeeper
[szk-repo]: https://github.com/slyphon/zookeeper/tree/dev/xplatform
[szk-repo-bundler]: https://github.com/slyphon/zookeeper/tree/dev/gemfile/
[szk-jar-gem]: https://rubygems.org/gems/slyphon-zookeeper_jar
[szk-jar-repo]: https://github.com/slyphon/zookeeper_jar

## Contacting the author

* Send me a github message (slyphon)
* I'm usually hanging out in IRC on freenode.net in #ruby-lang and in #zookeeper
* if you really want to, you can also reach me via twitter [@slyphon][]

[@slyphon]: https://twitter.com/#!/slyphon


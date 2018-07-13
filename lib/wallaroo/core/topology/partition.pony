/*

Copyright 2017 The Wallaroo Authors.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 implied. See the License for the specific language governing
 permissions and limitations under the License.

*/

use "collections"
use "files"
use "net"
use "wallaroo_labs/collection_helpers"
use "wallaroo_labs/equality"
use "wallaroo/core/boundary"
use "wallaroo/core/common"
use "wallaroo/ent/data_receiver"
use "wallaroo/ent/network"
use "wallaroo/ent/recovery"
use "wallaroo_labs/mort"
use "wallaroo/core/initialization"
use "wallaroo/core/metrics"
use "wallaroo/core/routing"
use "wallaroo/core/state"

class val Partition[In: Any val]
  let _function: PartitionFunction[In] val
  let _keys: Array[Key] val

  new val create(f: PartitionFunction[In] val,
    ks: Array[Key] val)
  =>
    _function = f
    _keys = ks

  fun function(): PartitionFunction[In] val => _function
  fun keys(): Array[Key] val => _keys

interface PartitionFunction[In: Any val]
  fun apply(input: In): Key

primitive SingleStepPartitionFunction[In: Any val] is
  PartitionFunction[In]
  fun apply(input: In): String => "key"

class val KeyDistribution is Equatable[KeyDistribution]
  let _hash_partitions: HashPartitions
  let _workers_to_keys: Map[String, Array[Key] val] val

  new val create(hp: HashPartitions, wtk: Map[String, Array[Key] val] val) =>
    _hash_partitions = hp
    _workers_to_keys = wtk

  fun claimants(): Iterator[String] =>
    _hash_partitions.claimants()

  fun hash_partitions(): HashPartitions =>
    _hash_partitions

  fun workers_to_keys(): Map[String, Array[Key] val] val =>
    _workers_to_keys

  fun update_key(key: Key, pa: ProxyAddress): KeyDistribution val =>
    let new_workers_to_keys = recover trn Map[String, Array[Key] val] end

    var old_key_target = ""
    for (w, ks) in _workers_to_keys.pairs() do
      new_workers_to_keys(w) = ks
      if ArrayHelpers[Key].contains[Key](ks, key) then
        old_key_target = w
      end
    end

    try
      if old_key_target != "" then
        let old_target_keys = _workers_to_keys(old_key_target)?
        let new_keys = recover trn Array[Key] end
        for k in old_target_keys.values() do
          if k != key then new_keys.push(k) end
        end
        new_workers_to_keys(old_key_target) = consume new_keys
      end

      let new_key_target = pa.worker
      let new_keys_for_new_target = recover trn Array[Key] end
      for k in _workers_to_keys(new_key_target)?.values() do
        new_keys_for_new_target.push(k)
      end
      new_keys_for_new_target.push(key)
      new_workers_to_keys(new_key_target) = consume new_keys_for_new_target
    else
      Fail()
    end

    KeyDistribution(_hash_partitions, consume new_workers_to_keys)

  fun eq(that: box->KeyDistribution): Bool =>
    _hash_partitions == that._hash_partitions

  fun ne(that: box->KeyDistribution): Bool => not eq(that)

interface StateAddresses
  fun apply(key: Key): (Step tag | ProxyRouter | None)
  fun register_routes(router: Router, route_builder: RouteBuilder)
  fun steps(): Array[Consumer] val

class KeyedStateAddresses
  let _addresses: Map[Key, (Step | ProxyRouter)] val

  new val create(a: Map[Key, (Step | ProxyRouter)] val) =>
    _addresses = a

  fun apply(key: Key): (Step | ProxyRouter | None) =>
    try
      _addresses(key)?
    else
      None
    end

  fun register_routes(router: Router, route_builder: RouteBuilder) =>
    for s in _addresses.values() do
      match s
      | let step: Step =>
        step.register_routes(router, route_builder)
      end
    end

  fun steps(): Array[Consumer] val =>
    let ss = recover trn Array[Consumer] end
    for s in _addresses.values() do
      match s
      | let cfcs: Consumer =>
        ss.push(cfcs)
      end
    end

    consume ss

trait val StateSubpartition is Equatable[StateSubpartition]
  fun build(app_name: String, worker_name: String,
    metrics_conn: MetricsSink,
    auth: AmbientAuth, event_log: EventLog,
    recovery_replayer: RecoveryReplayer,
    outgoing_boundaries: Map[String, OutgoingBoundary] val,
    initializables: SetIs[Initializable],
    data_routes: Map[U128, Consumer],
    keyed_data_routes: Map[Key, Step],
    keyed_step_ids: Map[Key, StepId]): PartitionRouter
  fun update_key(key: Key, pa: ProxyAddress): StateSubpartition ?
  fun runner_builder(): RunnerBuilder

class val KeyedStateSubpartition[PIn: Any val, S: State ref] is
  StateSubpartition
  let _state_name: String
  let _key_distribution: KeyDistribution
  let _id_map: Map[Key, U128] val
  let _partition_function: PartitionFunction[PIn] val
  let _pipeline_name: String
  let _runner_builder: RunnerBuilder

  new val create(state_name': String,
    key_distribution': KeyDistribution,
    id_map': Map[Key, U128] val, runner_builder': RunnerBuilder,
    partition_function': PartitionFunction[PIn] val,
    pipeline_name': String)
  =>
    _state_name = state_name'
    _key_distribution = key_distribution'
    _id_map = id_map'
    _partition_function = partition_function'
    _pipeline_name = pipeline_name'
    _runner_builder = runner_builder'

  fun runner_builder(): RunnerBuilder =>
    _runner_builder

  fun build(app_name: String, worker_name: String,
    metrics_conn: MetricsSink,
    auth: AmbientAuth, event_log: EventLog,
    recovery_replayer: RecoveryReplayer,
    outgoing_boundaries: Map[String, OutgoingBoundary] val,
    initializables: SetIs[Initializable],
    data_routes: Map[StepId, Consumer],
    keyed_data_routes: Map[Key, Step],
    keyed_step_ids: Map[Key, StepId]):
    LocalPartitionRouter[PIn, S] val
  =>
    let hashed_node_routes = recover trn Map[String, HashedProxyRouter] end

    let m = recover trn Map[Key, Step] end

    var partition_count: USize = 0

    for c in _key_distribution.claimants() do
      if c == worker_name then
        try
          let keys = _key_distribution.workers_to_keys()(c)?
          for key in keys.values() do
            try
              let id = _id_map(key)?
              let reporter = MetricsReporter(app_name, worker_name,
                metrics_conn)
              let next_state_step = Step(auth, _runner_builder(
                where event_log = event_log, auth = auth),
                consume reporter, id, _runner_builder.route_builder(),
                  event_log, recovery_replayer, outgoing_boundaries)

              initializables.set(next_state_step)
              data_routes(id) = next_state_step
              keyed_data_routes(key) = next_state_step
              keyed_step_ids(key) = id
              m(key) = next_state_step
              partition_count = partition_count + 1
            else
              @printf[I32](("Missing step id for " + key + "!\n").cstring())
            end
          end
        else
          @printf[I32](("Could not find keys for %s!\n").cstring(),
            c.cstring())
          Fail()
        end
      else
        try
          let boundary = outgoing_boundaries(c)?
          hashed_node_routes(c) = HashedProxyRouter(c, boundary,
            _state_name, auth)
        else
          @printf[I32](("Missing proxy for " + c + "!\n").cstring())
        end
      end
    end

    @printf[I32](("Spinning up " + partition_count.string() +
      " state partitions for " + _pipeline_name + " pipeline\n").cstring())

    LocalPartitionRouter[PIn, S](_state_name, worker_name, consume m,
      _id_map, consume hashed_node_routes,
      _key_distribution.hash_partitions(), _partition_function)

  fun update_key(key: Key, pa: ProxyAddress): StateSubpartition =>
    let kpa = _key_distribution.update_key(key, pa)
    KeyedStateSubpartition[PIn, S](_state_name, kpa, _id_map,
      _runner_builder, _partition_function, _pipeline_name)

  fun eq(that: box->StateSubpartition): Bool =>
    match that
    | let kss: box->KeyedStateSubpartition[PIn, S] =>
      // ASSUMPTION: Add RunnerBuilder equality check assumes that
      // runner builder would not change over time, which currently
      // is true.
      (_key_distribution == kss._key_distribution) and
        (MapEquality[Key, U128](_id_map, kss._id_map)) and
        (_partition_function is kss._partition_function) and
        (_pipeline_name == kss._pipeline_name) and
        (_runner_builder is kss._runner_builder)
    else
      false
    end

  fun ne(that: box->StateSubpartition): Bool => not eq(that)

primitive PartitionFileReader
  fun apply(filename: String, auth: AmbientAuth): Array[Key] val =>
    let keys = recover trn Array[Key] end

    try
      let file = File(FilePath(auth, filename)?)
      for line in file.lines() do
        let els = line.split(",")
        match els.size()
        | 0 => None
        | 1 => keys.push(els(0)?)
        // TODO: Remove this, since we no longer support weighted keys
        | 2 => keys.push(els(0)?)
        else
          error
        end
      end
      file.dispose()
    else
      @printf[I32](("ERROR: Problem reading partition file. Each line must " +
        "have a key string\n").cstring())
    end

    consume keys

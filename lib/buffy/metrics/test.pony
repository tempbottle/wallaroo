use "ponytest"
use "collections"
use "promises"
use "buffy/messages"
use "sendence/bytes"

actor Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make(env: Env) => None

  fun tag tests(test: PonyTest) =>
    test(_TestThroughputHistory)
    test(_TestMonitoringHubEncoder)

class iso _TestThroughputHistory is UnitTest
  fun name(): String => "buffy:ThroughputHistory"

  fun apply(h: TestHelper) =>
    let th = recover ref ThroughputHistory end
    let base: U64 = 1469658500_000000001
    let incr: U64 = 100_000_000
    let ceil: U64 = base + 10_000_000_000
    for v in Range[U64](base, ceil, incr) do
      th(v)
    end
    for (t, c) in th.values() do
      h.assert_eq[U64](c, 10)
    end
    true

class iso _TestMonitoringHubEncoder is UnitTest
  fun name(): String => "buffy:MonitoringHubEncoder"

  fun apply(h: TestHelper) ? =>
    h.long_test(1_000_000_000)
    let auth: AmbientAuth = h.env.root as AmbientAuth
    let app_name = "test app"

    // Set up metrics collection
    // use a test stream output
    let promise = Promise[Array[ByteSeq] val]
    promise.next[Array[ByteSeq] val](recover this~_fulfill(h) end)
    let output = MetricsAccumulatorActor(promise)
    let res = ResumableTest(output)
    let handler: MetricsCollectionOutputHandler iso =
      recover iso MetricsStringAccumulator(MonitoringHubEncoder, output,
        app_name) end

    let mc: MetricsCollection = MetricsCollection(1, consume handler)

    mc.process_step("1", 1000, 1999)
    mc.process_step("1", 2000, 2999)
    mc.process_step("1", 3000, 3999)
    mc.process_step("1", 4000, 4999)
    mc.process_step("1", 5000, 5999)

    mc.process_step("2", 1000, 1999)
    mc.process_step("2", 2000, 2999)
    mc.process_step("2", 3000, 3999)
    mc.process_step("2", 4000, 4999)
    mc.process_step("2", 5000, 5999)

    let sink = BoundaryTypes.source_sink()
    let egress = BoundaryTypes.ingress_egress()
    mc.process_sink("1", 1000, 2999)
    mc.process_sink("1", 1500, 3499)
    mc.process_sink("1", 2500, 6000)
    mc.process_sink("1", 2550, 5950)
    mc.process_boundary("1", 2000, 4000)

    // Process the collection with the handlers array
    mc.send_output(res)

  fun tag _fulfill(h: TestHelper, value: Array[ByteSeq] val):
    Array[ByteSeq] val
  =>
    // let arr = recover val value.array() end
    // h.assert_eq[USize](value.size(), 5375)
    /* TODO: Parse the JSON and validate contents:
    for chunk in LengthParser(value.array()) do
      h.assert
    end
    */
    h.complete(true)
    value

  fun timed_out(h: TestHelper) =>
    h.complete(false)

class LengthParser is Iterator[String]
  let _data: Array[U8 val] val
  var _idx: USize = 0

  new create(data: Array[U8 val] val) =>
    _data= data

  fun ref has_next(): Bool =>
    _idx <= _data.size()

  fun ref next(): String val ? =>
    let s = _idx = _idx + 4
    let slc = _data.slice(s, _idx)
    var chunk = bytes_to_usize(slc)
    let s' = _idx = _idx + chunk
    let slc' = _data.slice(s', _idx).clone()
    String.create().append(slc').clone()

  fun tag bytes_to_usize(a: Array[U8 val] ref): USize ? =>
    ((a(0).u32() << 24) + (a(1).u32() << 16) + (a(2).u32() << 8) +
    a(3).u32()).usize()

actor ResumableTest is Resumable
  let _output: MetricsAccumulatorActor  tag
  new create(output: MetricsAccumulatorActor tag) =>
    _output = output

  be resume() =>
    _output.written()

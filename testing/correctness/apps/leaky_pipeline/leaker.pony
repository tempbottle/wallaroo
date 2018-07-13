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

use "buffered"
use "collections"
use "options"
use "serialise"
use "wallaroo_labs/bytes"
use "wallaroo"
use "wallaroo/core/common"
use "wallaroo_labs/mort"
use "wallaroo/core/sink/tcp_sink"
use "wallaroo/core/source"
use "wallaroo/core/source/tcp_source"
use "wallaroo/core/state"
use "wallaroo/core/topology"

actor Main
  new create(env: Env) =>
    try
      let application = recover val
      Application("Hanging message sned")
      .new_pipeline[String,String]("Celsius Conversion",
        TCPSourceConfig[String].from_options(ConstDecoder,
        TCPSourceConfigCLIParser(env.args)?(0)?))
      .to_parallel[String]({(): Id => Id})
      .to_sink(TCPSinkConfig[String val].from_options(StringEncoder,
        TCPSinkConfigCLIParser(env.args)?(0)?))
      end
      Startup(env, application, "hanging-pipeline")
    else
      @printf[I32]("Couldn't build topology\n".cstring())
    end

primitive Id is Computation[String, String]
  fun apply(input: String): String =>
    input

  fun name(): String => "Return the same string"

primitive ConstDecoder is FramedSourceHandler[String]
  fun header_length(): USize => 4

  fun payload_length(data: Array[U8] iso): USize => 4

  fun decode(data: Array[U8] val): String ? =>
    let x = data(0)?
    let size: USize = 16085
                            // fails with 16085 == EXPECTED 16385
                            // works with 16084 == EXPECTED 16384
                            // works with 16083 == EXPECTED 16383
    let a = recover val Array[U8].init(1, size) end
    let s = String.from_array(a)
    @printf[I32]("decode ran\n".cstring())
    s

primitive StringEncoder
  fun apply(s: String, wb: Writer): Array[ByteSeq] val =>
    @printf[I32]("encode ran\n".cstring())
    wb.write(s)
    wb.done()

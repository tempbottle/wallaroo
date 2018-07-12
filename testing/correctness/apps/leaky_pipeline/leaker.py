from collections import namedtuple
from copy import deepcopy
import wallaroo

def application_setup(args):
    in_host, in_port = wallaroo.tcp_parse_input_addrs(args)[0]
    out_host, out_port = wallaroo.tcp_parse_output_addrs(args)[0]
    tcp_source = wallaroo.TCPSourceConfig(in_host, in_port, decoder)
    tcp_sink = wallaroo.TCPSinkConfig(out_host, out_port, encoder)

    ab = wallaroo.ApplicationBuilder("Leaky pipe application")
    ab.new_pipeline("Leaky pipe", tcp_source)
    ab.to_stateful(buffer_items, Buffer, "buffer")
    ab.to_parallel(p)
    ab.to_sink(tcp_sink)
    return ab.build()

@wallaroo.state_computation(name="state1")
def buffer_items(item, buffer):
    ret = buffer.update(item)
    return (ret, True)

@wallaroo.computation(name="parallel")
def p(item):
    return item

@wallaroo.decoder(header_length=4, length_fmt=">I")
def decoder(line):
    line = line.decode("utf-8")
    return line * 100

@wallaroo.encoder
def encoder(results):
    return "%s"%(results)

class Buffer():
    def __init__(self):
        self._items = []
    def update(self, thing):
        self._items.append(thing)
        if len(self._items) > 100:
            print "returning items"
            popped = deepcopy(self._items)
            self._items = []
            return popped
        else:
            return None

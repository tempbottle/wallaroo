from collections import namedtuple
from copy import deepcopy
import wallaroo
import os

# Set LIST_LENGTH to a number between 1 and 100
# to find where the limit is.

LIST_LENGTH=80

#LIST_LENGTH=80 : EXPECTING 15936 : WORKS
#LIST_LENGTH=82 : EXPECTING 16350 : WORKS
### 2^^14 == 16384 #### this seems to be the breaking point
#LIST_LENGTH=83 : EXPECTING 16557 : HANGS
#LIST_LENGTH=85 : EXPECTING 16971 : HANG
#LIST_LENGTH=87 : EXPECTING 17385 : HANG
#LIST_LENGTH=88 : EXPECTING 17592 : HANG


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
    if ret:
        print "stateful ran on %s"%(os.getpid())
    return (ret, True)

@wallaroo.computation(name="parallel")
def p(x):
    print "stateless ran on %s"%(os.getpid())
    return x

@wallaroo.decoder(header_length=4, length_fmt=">I")
def decoder(line):
    line = line.decode("utf-8")
    return(line * 100)

@wallaroo.encoder
def encoder(results):
    print ("encoder ran on %s"%(os.getpid()))
    return "NODE %s GOT %s results\n"%(os.getpid(), results)

class Buffer():
    def __init__(self):
        self._items = []
    # def update(self, thing):
    #     return thing
    def update(self, thing):
        self._items.append(thing)
        if len(self._items) > 100:
            print "returning items"
            popped = self._items[0:LIST_LENGTH]
            self._items = []
            return popped
        else:
            return None

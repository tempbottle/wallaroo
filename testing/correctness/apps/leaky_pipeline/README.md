# Leaky pipes

## howto:


### Terminal 1:

`data_receiver --listen 127.0.0.1:6666`

### Terminal 2:

`killall -9 machida; ./start.sh ; tail -f worker*log`

### Terminal 3:

`giles_sender --host 127.0.0.1:5555 --messages 200`


.. and watch memory usage go up until it eats up all available computronium.


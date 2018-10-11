gcc -Wl,-undefined,dynamic_lookup  -fPIC -shared -o show_binary.so show_binary.c -I $ERL_ROOT/usr/include

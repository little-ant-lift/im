-module(gen_mod).
-export([get_module_proc/2]).
-spec get_module_proc(binary(), {frontend, atom()} | atom()) -> atom().

get_module_proc(Host, {frontend, Base}) ->
    get_module_proc(<<"frontend_", Host/binary>>, Base);
get_module_proc(Host, Base) ->
    binary_to_atom(
      <<(erlang:atom_to_binary(Base, latin1))/binary, "_", Host/binary>>,
      latin1).

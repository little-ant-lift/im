CUR=`basename $PWD`

# ../ejabberd.wcy123/ebin ../ejabberd.wcy123/deps/*/ebin
erl -pa ../$CUR/ebin ../$CUR/test deps/*/ebin ../extauth_rpc/ebin ../extauth_rpc/deps/*/ebin test  $*

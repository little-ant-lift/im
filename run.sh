#!/bin/sh
CUR=`basename $PWD`

# ../ejabberd.wcy123/ebin ../ejabberd.wcy123/deps/*/ebin
if [ x`uname` == xDarwin ] ;then
   OPTS="+K true -smp auto +P 2500000 +spp true +sbwt none +swt low +sub true +zdbbl 2096000"
else
   OPTS="+K true -smp auto +P 2500000 +spp true +sbt db +sbwt none +swt low +sub true +zdbbl 2096000"
fi
## -ticktick port 8082 -msync web_port 8083 -msync port 6718

erl $OPTS -sname msync -pa deps/im_libs/apps/*/ebin ../$CUR/ebin ../$CUR/test deps/*/ebin  test  -config test/`hostname -s`.ct.config $*

##msync安装包生成
1.配置编译项
sh autogen.sh
 ./configure --enable-shard=no
2.编译
 make
3.生成release包，生成的安装包为目录./rel/msync
 make rel
##Ejabberd安装包生成
1.配置编译项
 sh autogen.sh
 ./configure --enable-zlib --enable-odbc --enable-mysql --enable-nif --enable-tools --disable-shard
2.编译
 make
3.生成release包，生成的安装包为目录./rel/ejabberd
 make rel
 

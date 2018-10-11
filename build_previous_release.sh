PREVIOUS_RELEASE=$1
if  test -d previous_release/$PREVIOUS_RELEASE ; then
    echo "previouse release $PREVIOUSE has been already built"
else
    mkdir previous_release 2>/dev/null
    git clone git@github.com:easemob/msync previous_release/$PREVIOUS_RELEASE
    cd previous_release/$PREVIOUS_RELEASE
    git checkout -f $PREVIOUS_RELEASE
    sh autogen.sh
    ./configure;
    ../../deps/rebar/rebar get-deps
    bash ../../generate_fingerprint.sh
    ../../deps/rebar/rebar compile
    ../../deps/rebar/rebar generate
fi

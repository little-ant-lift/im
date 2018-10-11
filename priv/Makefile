CXXFLAGS += -std=c++11
CXXFLAGS += -ggdb
CXXFLAGS += -Wall -Werror
CXXFLAGS += -I/usr/local/Cellar/boost/1.58.0/include
CXXFLAGS += -I/usr/local/Cellar/openssl/1.0.2d_1/include/
CXXFLAGS += -I/usr/local/include
CXXFLAGS += -I../submodule/easemob-share/msync/proto
CXXFLAGS += -Wno-unused-local-typedefs
CFLAGS += -ggdb
CFLAGS += -Wall -Werror

LDFLAGS := -L/usr/local/lib $(LDFLAGS)
LDFLAGS += -L/usr/local/Cellar/boost/1.58.0/lib
LDFLAGS += -L/usr/local/Cellar/openssl/1.0.2d_1/lib


CC_FILES += ackbody.pb.cc
CC_FILES += indication.pb.cc
CC_FILES += jid.pb.cc
CC_FILES += keyvalue.pb.cc
CC_FILES += message.pb.cc
CC_FILES += messagebody.pb.cc
CC_FILES += messagequeue.pb.cc
CC_FILES += request.pb.cc
CC_FILES += response.pb.cc
CC_FILES += root.pb.cc
CC_FILES += status.pb.cc
CC_FILES += sync.pb.cc
PROTO_CC_FILES := $(patsubst %.pb.cc, ../submodule/easemob-share/msync/proto/%.pb.cc, $(CC_FILES))
PROTO_OBJECTS := $(patsubst %.pb.cc, %.pb.o, $(CC_FILES))

all: pb msync_test

msync_test: msync_test.o msync_lib.o $(PROTO_OBJECTS)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $+ -lboost_program_options -lssl -lprotobuf -lreadline

$(PROTO_OBJECTS): %.o : ../submodule/easemob-share/msync/proto/%.cc
	$(CXX) $(CXXFLAGS) -c -o $@ $<

.PHONY: pb
pb:
	$(MAKE) -C ../submodule/easemob-share/msync/proto

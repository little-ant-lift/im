#include <cstdlib>
#include <cstring>
#include <iostream>
#include <ostream>
#include <vector>
#include <algorithm>
#include <iterator>
#include <functional>
#include <deque>
#include <cassert>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <unistd.h>
#include <thread>
#include <boost/program_options.hpp>
#include <boost/tokenizer.hpp>
//#include <readline/readline.h>
#include <mutex>
using namespace boost;
//#include <openssl/bio.h>
//#include <openssl/evp.h>

namespace po = boost::program_options;

#include "root.pb.h"
#include "ackbody.pb.h"
#include "indication.pb.h"
#include "jid.pb.h"
#include "keyvalue.pb.h"
#include "message.pb.h"
#include "messagebody.pb.h"
#include "messagequeue.pb.h"
#include "request.pb.h"
#include "response.pb.h"
#include "root.pb.h"
#include "status.pb.h"
#include "sync.pb.h"

using namespace std;

static void maybe_auto_reply(easemob::pb::PBRoot * my_recv_message);
static char * rl_gets ();
static void execute_command(const string& command1);
//static void on_receive_msg();
static bool login_without_guid();
static bool login_no_app();
static bool login_no_username();
static bool login_no_domain();
static bool login_no_client_resource();
static bool login_no_auth();
static bool login_no_cmd();
static bool login(int flag);
static int seq_num = 0;
static int my_connect(string hostname, int port);
static void my_send(int fd, easemob::pb::PBRoot  * root);
static easemob::pb::PBRoot * my_recv(int fd);
static void main_loop();
static void error(const char *msg);
int sockfd = 0;
string app_key;
string username;
string domain_name;
string client_resource;
string password;
string hostname;
string auth;
string body;
bool auto_response = false;
string peer_name;
bool is_interactive = false;
int port;
string cover_test;
mutex lock_recv_messages;
easemob::pb::PBRoot* recv_message = NULL;
vector<easemob::pb::PBMessageQueue> unread_messages;
deque<easemob::pb::PBRoot*> recv_messages;
vector<string> commands;
template<class T>
ostream& operator<<(ostream& os, const vector<T>& v)
{
    copy(v.begin(), v.end(), ostream_iterator<T>(os, " "));
    return os;
}
static void parse_command_line(int argc, char *argv[])
{
    po::options_description desc("Allowed options");
    desc.add_options()
        ("help", "produce help message")
        ("appkey,a", po::value<string>(&app_key)->default_value(string("easemob-demo#chatdemoui")),
         "set user name")
        ("username,u", po::value<string>(&username)->default_value(string("myuser1")),
         "set user name")
        ("domain,d", po::value<string>(&domain_name)->default_value(string("easemob.com")),
         "set user domain name")
        ("client_resource,u", po::value<string>(&client_resource)->default_value(string("mobile")),
         "set user name")
        ("auth,a", po::value< string >(&auth)->default_value(string("secret")),
         "set auth token")
        ("password,p", po::value< string >(&password)->default_value(string("123456")),
         "set password")
        ("host,h", po::value< string >(&hostname)->default_value(string("localhost")),
         "msync hostname")
        ("message-body,m", po::value<string>(&body)->default_value(string("hello world")),
         "message body")
        ("port,P", po::value< int >(&port)->default_value(6717),
         "msync port")
        ("test-case,C",  po::value< string > (&cover_test)->default_value(string("no")),
         "msync port")
        ("command,c",  po::value<  vector<string > >(&commands)->composing()->multitoken(),
         "msync port")
        ("auto-response",  po::value< bool >(&auto_response)->default_value(false),
         "automatically reply a notify request")
        ("peer",  po::value< string >(&peer_name)->default_value("myuser1"),
         "set the other party's name")
        ("interactive,i",  po::value< bool >(&is_interactive)->default_value(false),
         "start interactive shell")
        ;
    po::variables_map vm;
    po::store(po::parse_command_line(argc, argv, desc), vm);
    po::notify(vm);
    if (vm.count("help")) {
        cout << desc << "\n";
        exit(1);
    }else{
    }
}
void my_sleep(unsigned int milli_seconds)
{
    const struct timespec x = {
        milli_seconds / 1000,
        (milli_seconds % 1000) * 1000 * 1000
    };
    nanosleep(&x,NULL);
}
int main(int argc, char *argv[])
{
    GOOGLE_PROTOBUF_VERIFY_VERSION;
    parse_command_line(argc,argv);
    sockfd = my_connect(hostname,port);
    bool exit_flag = false;
    std::thread t([exit_flag](){
            easemob::pb::PBRoot * my_recv_message = NULL;
            while(1){
                my_recv_message = my_recv(sockfd);
                if(my_recv_message){
                    maybe_auto_reply(my_recv_message);
                    lock_recv_messages.lock();
                    if(0) cout << "push recv pb \n"
                         << my_recv_message->DebugString()
                         << endl;
                    recv_messages.push_back(my_recv_message);
                    lock_recv_messages.unlock();
                }else{
                    break;
                }
            }
        });
    main_loop();
    close(sockfd);
    my_sleep(100);
    t.join();
    cout << "test is passed" << endl;
    return 0;
}
static bool login_without_guid()
{
    return login(0);
}
static bool login_no_app()
{
    return login(2);
}
static bool login_no_username()
{
    return login(3);
}
static bool login_no_domain()
{
    return login(4);
}
static bool login_no_client_resource()
{
    return login(5);
}
static bool login_no_auth()
{
    return login(6);
}
static bool login_no_cmd()
{
    return login(7);
}
static bool login(int flag)
{
    easemob::pb::PBRoot root;
    root.set_version(easemob::pb::PBRoot_Version_MSYNC_V1);
    if(flag > 0){ root.mutable_guid();                    }
    if(flag > 1){
        root.set_command(easemob::pb::PBRoot::REQUEST);
        auto request = root.mutable_request();
        auto sync = request->mutable_sync();
        request->set_seq_num(seq_num++);
        //auto get_unread =
        sync->mutable_get_unread();
    }
    if(flag > 2){ root.mutable_guid()->set_app_key(app_key); }
    if(flag > 3){ root.mutable_guid()->set_name(username);}
    if(flag > 4){ root.mutable_guid()->set_domain(domain_name);}
    if(flag > 5){ root.mutable_guid()->set_client_resource(client_resource); }
    if(flag > 6){ root.set_auth(auth); }
    //if(flag > 7){ root.set_command(easemob::pb::PBRoot::REQUEST); }
    my_send(sockfd,&root);
    return true;
}
static int my_connect(string hostname, int portno)
{
    int sockfd;
    struct sockaddr_in serv_addr;
    struct hostent *server;
    sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0)
        error("ERROR opening socket");
    server = gethostbyname(hostname.c_str());
    if (server == NULL) {
        fprintf(stderr,"ERROR, no such host\n");
        exit(0);
    }
    bzero((char *) &serv_addr, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    bcopy((char *)server->h_addr,
         (char *)&serv_addr.sin_addr.s_addr,
         server->h_length);
    serv_addr.sin_port = htons(portno);
    if (connect(sockfd,(struct sockaddr *) &serv_addr,sizeof(serv_addr)) < 0)
        error("ERROR connecting");
    return sockfd;
}

static void error(const char *msg)
{
    perror(msg);
    exit(0);
}

static void main_loop()
{
    for( vector<string>::iterator it = commands.begin();it!=commands.end();++it){
        execute_command(*it);
    }
    if(is_interactive){
        string command = rl_gets();
        while(command!="exit"){
            execute_command(command);
            command =  rl_gets();
        }
    }
    return;
}
static string generate_id()
{
    ostringstream s;
    s << static_cast<uint64_t>(time(NULL));
    return s.str();
}
static void notify_message(vector<string>& args)
{
    const std::set<string> flags(args.begin()+1, args.end());
    easemob::pb::PBRoot root;
    do {
        easemob::pb::PBRequest * request = nullptr;
        easemob::pb::PBMessage * message = nullptr;
        easemob::pb::PBJID * to = nullptr;
        root.set_version(easemob::pb::PBRoot::MSYNC_V1);
        root.set_command(easemob::pb::PBRoot::REQUEST);
        request = root.mutable_request();
        request->set_seq_num(seq_num++);
        if(flags.find("ignore_message") == flags.end()){
            message = request->mutable_message();
            if(flags.find("ignore_message_id") == flags.end()) {
                message->set_message_id(generate_id());
            }
            if(flags.find("ignore_message_to") == flags.end()) {
                to = message->mutable_to();
                if(flags.find("ignore_app_key") == flags.end()) {
                    to->set_app_key(string("easemob-demo#chatdemoui"));
                }
                if(flags.find("ignore_name") == flags.end()){
                    to->set_name(peer_name);
                }
                if(flags.find("ignore_domain") == flags.end()){
                    to->set_domain(string("easemob.com"));
                }
                if(flags.find("ignore_client_resource") == flags.end()){
                    to->set_client_resource(client_resource);
                }
            }
            if(flags.find("ignore_timestamp") == flags.end()){
                message->set_timestamp(10000);
            }
            if(flags.find("ignore_type") == flags.end()){
                message->set_type(easemob::pb::PBMessage::PBMessage::SINGLE_CHAT);
            }
            if(flags.find("ignore_body") == flags.end()){
                easemob::pb::PBMessageBody * mb =  message->mutable_body();
                easemob::pb::PBMessageBody::Content* content = mb->add_contents();
                content->set_type(easemob::pb::PBMessageBody::Content::TEXT);
                const string text = "hello";
                content->set_text(text);
            }
        }
    }while(0);
    my_send(sockfd,&root);
}
static void notify_wrong_payload(vector<string>& args)
{
    easemob::pb::PBRoot root;
    root.set_version(easemob::pb::PBRoot_Version_MSYNC_V1);
    root.set_command(easemob::pb::PBRoot::REQUEST);
    root.mutable_response();
    my_send(sockfd,&root);
}
static void send_message(vector<string>& args)
{
    easemob::pb::PBRoot root;
    string text = args.size() >=2?args[1]:body;
    easemob::pb::PBRequest * request = nullptr;
    easemob::pb::PBMessage * message_body = nullptr;
    easemob::pb::PBJID * to = nullptr;
    root.set_version(easemob::pb::PBRoot::MSYNC_V1);
    root.set_command(easemob::pb::PBRoot::REQUEST);
    request = root.mutable_request();
    request->set_seq_num(seq_num++);
    message_body = request->mutable_message();
    message_body->set_message_id(generate_id());
    to = message_body->mutable_to();
    to->set_app_key(string("easemob-demo#chatdemoui"));
    message_body->set_timestamp(10000);
    to->set_name(peer_name);
    to->set_domain(string("easemob.com"));
    to->set_client_resource(client_resource);
    message_body->set_type(easemob::pb::PBMessage::PBMessage::SINGLE_CHAT);
    easemob::pb::PBMessageBody * mb =  message_body->mutable_body();
    easemob::pb::PBMessageBody::Content* content = mb->add_contents();
    content->set_type(easemob::pb::PBMessageBody::Content::TEXT);
    content->set_text(text);
    my_send(sockfd,&root);
}
static string error_code_to_string(easemob::pb::PBStatus::ErrorCode X)
{
    string ret = "";
    switch (X) {
    case easemob::pb::PBStatus::OK: ret = "OK"; break;
    case easemob::pb::PBStatus::FAIL: ret = "FAIL"; break;
    case easemob::pb::PBStatus::UNAUTHORIZED: ret = "UNAUTHORIZED"; break;
    case easemob::pb::PBStatus::MISSING_PARAMETER: ret = "MISSING_PARAMETER"; break;
    case easemob::pb::PBStatus::WRONG_PARAMETER: ret = "WRONG_PARAMETER"; break;
    case easemob::pb::PBStatus::REDIRECT: ret = "REDIRECT"; break;
    case easemob::pb::PBStatus::NO_SUCH_GROUP: ret = "NO_SUCH_GROUP"; break;
    case easemob::pb::PBStatus::PERMISSION_DENIED: ret = "PERMISSION_DENIED"; break;
    case easemob::pb::PBStatus::NO_ROUTE: ret = "NO_ROUTE"; break;
    case easemob::pb::PBStatus::UNKNOWN_COMMAND: ret = "UNKNOWN_COMMAND"; break;
    default: ret = "UNKNOWN";
    }
    return ret;
}
static void expect_status(vector<string>& args)
{
    if(!recv_message->has_response()){
        cout << "expecting a response, but no response\n"
             << endl;
        assert(false);
    }
    const easemob::pb::PBResponse & response_message  = (recv_message->response());
    string error_code = args.size() >=2?args[1]:string("");
    string reason = args.size()>=3?args[2]:string("");
    if(error_code == ""){
        if(response_message.has_status()){
            cout << "expecting no status, but status is given as below.\n"
                 << response_message.status().DebugString()
                 << endl;
            assert(false);
        }
    }else{
        if(!response_message.has_status()){
            cout << "expecint a status, have no status" << endl;
            assert(false);
        }
        if(!response_message.status().has_error_code()){
            cout << "have no error code" << endl; assert(false);
        }
        string x_error_code = error_code_to_string(response_message.status().error_code());
        if(error_code != x_error_code){
            cout << "unexpeced error code: expecting " << error_code << " but " << x_error_code << " is given." << endl;
            assert(false);
        }
        if(reason == ""){
            if(response_message.status().has_reason()){
                cout << "sorry, I don't expect any reason, but reason \"" << response_message.status().reason() << "\" is given." << endl;
                assert(false);
            }
        }else{
            if(!response_message.status().has_reason()){
                cout << "expecting reason \"" << reason << "\", but no reason is given." << endl;
                assert(false);
            }else{
                if(reason != response_message.status().reason() ){
                    cout << "expecting reason \"" << reason << "\", but the given reason is \"" << response_message.status().reason() << "\"."  << endl;
                    assert(false);
                }
            }
        }
        cout << "expect status " << args << " OK " << endl;
    }
    return;
}
static void expect_message(vector<string>& args)
{
    if(!recv_message->has_request()){
        cout << "expect notify request body, but fail.\n"
             << recv_message->DebugString()
             << endl;
        assert(false);
    }
    if(!recv_message->request().has_message()){
        cout << "expect notify request message body" << endl;
        assert(false);
    }
    if(!recv_message->request().message().has_message_id()){
        cout << "expect notify request message id" << endl;
        assert(false);
    }
    // string id = recv_message->request().message().message_id();

    // easemob::pb::PBRoot root;
    // root.set_version(::easemob::pb::PBRoot::MSYNC_V1);
    // root.set_command(::easemob::pb::PBRoot::RESPONSE);
    // ::easemob::pb::PBResponse* r = root.mutable_response();
    // r->mutable_ack_body()->set_message_id(id);
    // my_send(sockfd,&root);
}

static void cmd_sleep(vector<string>& args)
{
    int x = args.size() >=2?atoi(args[1].c_str()):1;
    sleep(static_cast<unsigned int>(x));
    return;
}
static void cmd_recv(vector<string>& args)
{
    easemob::pb::PBRoot * my_recv_message = NULL;
    while(my_recv_message == NULL){
        lock_recv_messages.lock();
        if(!recv_messages.empty()){
            my_recv_message = recv_messages.front();
            recv_messages.pop_front();
            if(is_interactive)
                cout << "pop recv message\n"
                     << my_recv_message->DebugString()
                     << endl;
        }else{
            recv_message = NULL;
        }
        lock_recv_messages.unlock();
        my_sleep(1);
    }
    if(recv_message) delete recv_message;
    recv_message = my_recv_message;
}
static string pbjid_to_string(const ::easemob::pb::PBJID & id)
{
    string ret;
    if(id.has_app_key()){
        ret += id.app_key();
    }
    if(id.has_name()){
        ret += "_";
        ret += id.name();
    }
    if(id.has_domain()){
        ret += "@";
        ret += id.domain();
    }
    if(id.has_client_resource()){
        ret += "/";
        ret += id.client_resource();
    }
    return ret;
}
static void expect_unread_list(vector<string>& args)
{
    int total = args.size() >=2?atoi(args[1].c_str()):0;
    if(!recv_message->has_response()){
        cout << "expect get unread response" << endl;
        assert(false);
    }
    auto response = recv_message->response();
    if(!response.has_status()){
        cout << "expect get unread response has status" << endl;
        assert(false);
    }
    auto status = response.status();
    if(!status.has_error_code()){
        cout << "response has no status code" << endl;
        assert(false);
    }
    auto error_code = status.error_code();
    if(error_code != ::easemob::pb::PBStatus::OK){
        cout << "expect get unread response has error code OK" << endl;
        assert(false);
    }
    if(total != 0) {
        auto sync = response.sync();
        if(!response.has_sync()){
            cout << "expect sync response fail" << endl;
            assert(false);
        };
        if(sync.queues().empty()){
            cout << "expect sync response has non-empty queue" << endl;
            assert(false);
        }
        auto messages = sync.queues();
        for(auto i = messages.begin(); i != messages.end(); ++i){
            unread_messages.push_back(*i);
        }
        cout << "unread messages:\n";
        int recv_total = 0;
        for(auto i2 = unread_messages.begin(); i2 != unread_messages.end(); ++i2){
            recv_total += i2->n();
            cout << "     "
                 << pbjid_to_string(i2->queue()) << ":"
                 << i2->n() << " messages\n";
        }
        if(recv_total!=total){
            cout << "expecting " << total << " unread messages, but got " << recv_total << " messages\n";
            assert(false);
        }
    }else{
        if(response.has_sync() && !response.sync().queues().empty()){
            cout << "expecting zero unread messages, but got something\n";
            assert(false);
        }
    }
    cout << endl;
}
static void sync_offline_1(const ::easemob::pb::PBMessageQueue & unread_msg)
{
    auto id = unread_msg.queue();
    cout << "    syncing  " << pbjid_to_string(id)
         << unread_msg.DebugString()
         << "\n";
    easemob::pb::PBRoot root;
    do {
        root.set_version(easemob::pb::PBRoot_Version_MSYNC_V1);
        root.set_command(easemob::pb::PBRoot::REQUEST);
        auto req = root.mutable_request();
        req->set_seq_num(seq_num++);
        auto sync = req->mutable_sync();
        auto get_messages = sync->mutable_get_messages();
        auto queue = get_messages->mutable_queue();
        *queue = unread_msg;
    }while(0);
    my_send(sockfd,&root);
}
static void sync_offline(vector<string>& args)
{
    cout << "syncing offline message\n";
    for(auto i2 = unread_messages.begin(); i2 != unread_messages.end(); ++i2){
        sync_offline_1(*i2);
    }
    cout << endl;
}
typedef tokenizer<escaped_list_separator<char> > Tok;
static void execute_command(const string& command1)
{
    char_separator<char> sep("-;| \t");
    Tok tok(command1);
    vector<string> command2;
    for(Tok::iterator beg=tok.begin(); beg!=tok.end();++beg){
        command2.push_back(*beg);
    }

    if(command2.empty()){

    }else if(command2.front() == "expect_status") {
        expect_status(command2);
    }else if(command2.front() == "expect_message") {
        expect_message(command2);
    }else if(command2.front() == "login_no_guid") {
        login_without_guid();
    }else if(command2.front() == "login_no_app"){
        login_no_app();
    }else if(command2.front() == "login_no_username"){
        login_no_username();
    }else if(command2.front() == "login_no_domain"){
        login_no_domain();
    }else if(command2.front() == "login_no_client_resource"){
        login_no_client_resource();
    }else if(command2.front() == "login_no_auth"){
        login_no_auth();
    }else if(command2.front() == "login_no_cmd"){
        login_no_cmd();
    }else if(command2.front() == "login"){
        login(100);
    }else if(command2.front() == "notify_message"){
        notify_message(command2);
    }else if(command2.front() == "notify_wrong_payload"){
        notify_wrong_payload(command2);
    }else if(command2.front() == "expect_unread_list"){
        expect_unread_list(command2);
    }else if(command2.front() == "sync_offline"){
        sync_offline(command2);
    }else if(command2.front() == "recv") {
        // it does not work any longer, becase a dedicate thread is receiving.
        cmd_recv(command2);
    }else if(command2.front() == "send") {
        send_message(command2);
    }else if(command2.front() == "sleep") {
        cmd_sleep(command2);
    }else {
        if(is_interactive){
            command2.clear();
            command2.push_back(string("send"));
            command2.push_back(command1);
            send_message(command2);
        }else{
            cout << "unknown command: " << command2 << endl;
            assert(false);
        }
    }
}
static void my_send(int fd, easemob::pb::PBRoot  * root)
{
    string buffer;
    root->SerializeToString(&buffer);
    string out;
    uint32_t buf_size = static_cast<uint32_t>( buffer.size());
    // in big endian format
    out.push_back(static_cast<unsigned char>( (buf_size>>24) & 0xFF));
    out.push_back(static_cast<unsigned char>( (buf_size>>16) & 0xFF));
    out.push_back(static_cast<unsigned char>( (buf_size>> 8) & 0xFF));
    out.push_back(static_cast<unsigned char>( (buf_size>> 0) & 0xFF));
    out += buffer;

    ssize_t total_size = out.size();
    const char * p = out.c_str();

    // dump before sending
    cout << "send " << total_size <<  " bytes:";
    for(int i = 0; i < 4 ; ++i){
        fprintf(stdout,"0x%02x ", static_cast<unsigned char>(p[i]));
    }
    for(int i = 0; i < total_size - 4 ; ++i){
        if(i%16 == 0){
            fprintf(stdout,"\n");
        }
        fprintf(stdout,"0x%02x ", static_cast<unsigned char>(p[i + 4]));
    }
    cout << "\n";
    cout << "PB Message:" << "\n"
         << root->DebugString()
         << endl;

    // ok start to send

    ssize_t r = 0;
    ssize_t rtmp = 0;
    do{ rtmp = write(fd, p + r, total_size - r);
        assert(rtmp >= 0);
        r += rtmp;
        if(0)cerr <<  __FILE__ << ":" << __LINE__ << ": [" << __FUNCTION__<< "] "
             << "r "  << r << " "
             << "rtmp "  << rtmp << " "
             << "total_size "  << total_size << " "
             << "buf_size "  << buf_size << " "
             << endl;
    }while(r < buf_size);

    return;
}
static void maybe_auto_reply(easemob::pb::PBRoot * my_recv_message)
{
    // if(!my_recv_message->has_command()){
    //     return;
    // }
    // if(my_recv_message->command() != easemob::pb::PBRoot::REQUEST){
    //     return;
    // }
    if(!my_recv_message->has_request()){
        return;
    }
    auto request = my_recv_message->request();
    if(!request.has_message()){
        return;
    }
    auto message = request.message();
    string id = message.message_id();

    easemob::pb::PBRoot root;
    root.set_version(easemob::pb::PBRoot::MSYNC_V1);
    root.set_command(easemob::pb::PBRoot::RESPONSE);
    auto response = root.mutable_response();
    auto ack_body = response->mutable_ack_body();
    ack_body->set_message_id(id);

    auto * status =  response->mutable_status();
    status->set_error_code(::easemob::pb::PBStatus::OK);
    if(request.has_seq_num()){
        response->set_seq_num(request.seq_num());
    }
    my_send(sockfd,&root);
    if(message.has_body()){
        auto contents = message.body().contents();
        for(auto it = contents.begin(); it != contents.end() ; ++it){
            if(it->has_text()){
                cout << "**** recv message ***\n"
                     << it->text()
                     << endl;
            }
        }
    }
}
static easemob::pb::PBRoot * my_recv(int fd)
{
    unsigned char buf_hd[4];
    ssize_t rtmp = 0;
    rtmp = read(fd, buf_hd, 4);
    if(rtmp == 0 || rtmp == -1){
        return NULL;
    }
    assert(rtmp == 4);
    ssize_t buf_size = (buf_hd[0] << 24) + (buf_hd[1] << 16) +     (buf_hd[2] << 8) + buf_hd[3];
    ssize_t msg_size = buf_size;
    char msg_buf[msg_size+1];
    ssize_t r = 0;
    cout << "recv " << buf_size << " bytes: ";
    for(int i = 0; i < 4 ; ++i){
        fprintf(stdout,"0x%02x ", static_cast<unsigned char>(buf_hd[i]));
    }
    do{ rtmp = read(fd, msg_buf + r, msg_size - r);
        r += rtmp;
        if(0)cerr <<  __FILE__ << ":" << __LINE__ << ": [" << __FUNCTION__<< "] "
             << "r "  << r << " "
             << "rtmp "  << rtmp << " "
             << "msg_size "  << msg_size << " "
             << "buf_size "  << buf_size << " "
             << endl;
        assert(rtmp>=0);
    }while(r < msg_size);
    for(int i = 0; i < msg_size ; ++i){
        if(i%16 == 0){
            fprintf(stdout,"\n");
        }
        fprintf(stdout,"0x%02x ", static_cast<unsigned char>(msg_buf[i]));
    }
    cout << "\n";

    easemob::pb::PBRoot * ret = new easemob::pb::PBRoot();
    int ok = ret->ParseFromArray(msg_buf,msg_size);
    cout << "PB decode " << (ok?"ok":"fail") << "\n";
    if(ok){
        cout << "PB Message:" << "\n"
             << ret->DebugString()
             << endl;
    }
    return ret;
}

/* A static variable for holding the line. */
//static char *line_read = (char *)NULL;

/* Read a string, and return a pointer to it.  Returns NULL on EOF. */
static char * rl_gets ()
{
    /* If the buffer has already been allocated, return the memory
       to the free pool. */
    // if (line_read)
    // {
    //     free (line_read);
    //     line_read = (char *)NULL;
    // }

    /* Get a line from the user. */
    //line_read = readline ("");
    //line_read = fgets(line_read)

    /* If the line has any text in it, save it on the history. */
    // if (line_read && *line_read)
    //     add_history (line_read);
    static char line_read[1024];
    fgets(line_read,1024,stdin);
    for(int i = 0; i < 1024; ++i){
        if(line_read[i] == '\n') {
            line_read[i] = '\0';
        }
    }
    return (line_read);
}

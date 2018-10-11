#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
enum msync_version_e {
    MSYNC_VER_RESERVE_0 = 0,
    MSYNC_VER_1 = 1,
    MSYNC_VER_2 = 2,
    MSYNC_VER_RESERVE_3 = 3,
    MSYNC_VER_RESERVE_4 = 4,
    MSYNC_VER_RESERVE_5 = 5,
    MSYNC_VER_RESERVE_6 = 6,
    MSYNC_VER_RESERVE_7 = 7,
    MSYNC_VER_RESERVE_8 = 8,
    MSYNC_VER_RESERVE_9 = 9,
    MSYNC_VER_RESERVE_10 = 10,
    MSYNC_VER_RESERVE_11 = 11,
    MSYNC_VER_RESERVE_12 = 12,
    MSYNC_VER_RESERVE_13 = 13,
    MSYNC_VER_RESERVE_14 = 14,
    MSYNC_VER_RESERVE_15 = 15
};
enum msync_command_e {
    MSYNC_CMD_SYNC = 0,
    MSYNC_CMD_PROVISION = 1,
    MSYNC_CMD_GET_UNREAD = 2,
    MSYNC_CMD_RESERVE_3 = 3,
    MSYNC_CMD_RESERVE_4 = 4,
    MSYNC_CMD_RESERVE_5 = 5,
    MSYNC_CMD_RESERVE_6 = 6,
    MSYNC_CMD_RESERVE_7 = 7,
    MSYNC_CMD_RESERVE_8 = 8,
    MSYNC_CMD_RESERVE_9 = 9,
    MSYNC_CMD_RESERVE_10 = 10,
    MSYNC_CMD_RESERVE_11 = 11,
    MSYNC_CMD_RESERVE_12 = 12,
    MSYNC_CMD_RESERVE_13 = 13,
    MSYNC_CMD_RESERVE_14 = 14,
    MSYNC_CMD_RESERVE_15 = 15
};
enum msync_tag_e {
    MSYNC_TAG_USER_AGENT = 0,
    MSYNC_TAG_GUID = 1,
    MSYNC_TAG_POV = 2,          // period of validality
    MSYNC_TAG_AUTH = 3
};
enum msync_encoding_e {
    MSYNC_ENCODING_JSON = 0, // JSON absence means json, for debug
    MSYNC_ENCODING_PB = 1,// protobuf,
    MSYNC_ENCODING_FB = 2,// flatbuffer,
    MSYNC_ENCODING_BSON = 3  // bson or else,
};
struct msync_header_tlv_s {
    uint8_t tag;
    uint8_t length;
    uint8_t value[];
};
struct msync_header_s {
    unsigned int version: 4;
    unsigned int command: 4;
    unsigned int crypto:  4;
    unsigned int encoding: 4;
    uint16_t     payload_length;
    struct msync_header_tlv_s tlv[];
};

struct msync_header_s * msync_create_header(enum msync_version_e ver,
                                            enum msync_command_e cmd,
                                            int crypto,
                                            enum msync_encoding_e encoding);

struct msync_header_s * msync_set_user_agent(struct msync_header_s * h, const char * ua, size_t len);
struct msync_header_s * msync_set_guid(struct msync_header_s * h, const char * guid,size_t len);
struct msync_header_s * msync_set_pov(struct msync_header_s * h, const char * pov,size_t len);
struct msync_header_s * msync_set_auth(struct msync_header_s * h, const char * auth,size_t len);
#ifdef __cplusplus
}
#endif

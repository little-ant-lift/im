#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include "msync_lib.h"

#define LAST_TLV(h) ((struct msync_header_tlv_s*)(((char*)(h)) + sizeof(struct msync_header_s) + (h)->payload_length))

struct msync_header_s * msync_create_header(enum msync_version_e ver,
                                     enum msync_command_e cmd,
                                     int crypto,
                                     enum msync_encoding_e encoding)
{
    struct msync_header_s * ret = (struct msync_header_s *) malloc(sizeof(struct msync_header_s));
    if(!ret) abort();
    ret->version = ver;
    ret->command = cmd;
    ret->crypto = crypto;
    ret->encoding = encoding;
    ret->payload_length = 0;
    return ret;
}

static struct msync_header_s * msync_set_tlv(struct msync_header_s * h, enum msync_tag_e tag, const char * value, size_t len)
{
    size_t tlv_size = sizeof(struct msync_header_tlv_s) + len;
    assert(tlv_size < UINT8_MAX);
    size_t old_size = sizeof(struct msync_header_s) + h->payload_length;
    size_t new_size = old_size + tlv_size;
    assert(new_size < UINT16_MAX);
    h = (struct msync_header_s*)realloc((void*)h, new_size);
    struct msync_header_tlv_s *tlv = LAST_TLV(h);
    tlv->tag = tag;
    tlv->length = (uint8_t) len;
    h->payload_length += tlv_size;
    memcpy(tlv->value, value, len);
    return h;
}
struct msync_header_s * msync_set_user_agent(struct msync_header_s * h, const char * ua,size_t len)
{
    return msync_set_tlv(h,MSYNC_TAG_USER_AGENT,ua,len);
}
struct msync_header_s * msync_set_auth(struct msync_header_s * h, const char * auth,size_t len)
{
    return msync_set_tlv(h,MSYNC_TAG_AUTH,auth,len);
}
struct msync_header_s * msync_set_pov(struct msync_header_s * h, const char * pov, size_t len)
{
    return msync_set_tlv(h,MSYNC_TAG_POV,pov,len);
}
struct msync_header_s * msync_set_guid(struct msync_header_s * h, const char * guid,size_t len)
{
    return msync_set_tlv(h,MSYNC_TAG_GUID,guid,len);
}

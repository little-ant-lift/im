#!/bin/bash
SysConfig=$1

PERSISTENT_REDIS="${PERSISTENT_REDIS:-redis}"
PERSISTENT_REDIS_PORT="${PERSISTENT_REDIS_PORT:-6379}"
CACHED_REDIS="${CACHED_REDIS:-redis}"
CACHED_REDIS_PORT="${CACHED_REDIS_PORT:-6379}"

HEALTH_SERVER="${HEALTH_SERVER:-127.0.0.1}"
sed -i "s/\$(health_server)/${HEALTH_SERVER}/g" ${SysConfig}
HEALTH_SERVER_PORT="${HEALTH_SERVER_PORT:-8080}"
sed -i "s/\$(health_server_port)/${HEALTH_SERVER_PORT}/g" ${SysConfig}

TURN_SERVER="${TURN_SERVER:-127.0.0.1:3478}"
sed -i "s/\$(turn_server)/${TURN_SERVER}/g" ${SysConfig}

WEBRTC_CONFERENCE="${WEBRTC_CONFERENCE:-webrtc-conference}"
sed -i "s/\$(webrtc_conference)/${WEBRTC_CONFERENCE}/g" ${SysConfig}
WEBRTC_CONFERENCE_PORT="${WEBRTC_CONFERENCE_PORT:-6996}"
sed -i "s/\$(webrtc_conference_port)/${WEBRTC_CONFERENCE_PORT}/g" ${SysConfig}

WEBRTC_RTCSERVER="${WEBRTC_RTCSERVER:-webrtc-rtcserver}"
sed -i "s/\$(webrtc_rtcserver)/${WEBRTC_RTCSERVER}/g" ${SysConfig}

WEBRTC_RTCSERVER_PORT="${WEBRTC_RTCSERVER_PORT:-7996}"
sed -i "s/\$(webrtc_rtcserver_port)/${WEBRTC_RTCSERVER_PORT}/g" ${SysConfig}

IM_THRIFT_SERVER="${IM_THRIFT_SERVER:-thrift}"
sed -i "s/\$(im_thrift_server)/${IM_THRIFT_SERVER}/g" ${SysConfig}
IM_THRIFT_PORT="${IM_THRIFT_PORT:-9999}"
sed -i "s/\$(im_thrift_port)/${IM_THRIFT_PORT}/g" ${SysConfig}

IM_THRIFT_GROUP_SERVER="${IM_THRIFT_GROUP_SERVER:-thrift-group}"
sed -i "s/\$(im_thrift_group_server)/${IM_THRIFT_GROUP_SERVER}/g" ${SysConfig}
IM_THRIFT_GROUP_PORT="${IM_THRIFT_GROUP_PORT:-10999}"
sed -i "s/\$(im_thrift_group_port)/${IM_THRIFT_GROUP_PORT}/g" ${SysConfig}

ANTISPAM_BEHAVIOR_SERVER="${ANTISPAM_BEHAVIOR_SERVER:-antispam}"
sed -i "s/\$(antispam_behavior_server)/${ANTISPAM_BEHAVIOR_SERVER}/g" ${SysConfig}
ANTISPAM_BEHAVIOR_PORT="${ANTISPAM_BEHAVIOR_PORT:-9595}"
sed -i "s/\$(antispam_behavior_port)/${ANTISPAM_BEHAVIOR_PORT}/g" ${SysConfig}

ANTISPAM_TEXT_PARSE_SERVER="${ANTISPAM_TEXT_PARSE_SERVER:-antispam}"
sed -i "s/\$(antispam_text_parse_server)/${ANTISPAM_TEXT_PARSE_SERVER}/g" ${SysConfig}
ANTISPAM_TEXT_PARSE_PORT="${ANTISPAM_TEXT_PARSE_PORT:-8090}"
sed -i "s/\$(antispam_text_parse_port)/${ANTISPAM_TEXT_PARSE_PORT}/g" ${SysConfig}

KAFKA="${KAFKA:-kafka}"
sed -i "s/\$(kafka)/${KAFKA}/g" ${SysConfig}
KAFKA_PORT="${KAFKA_PORT:-9092}"
sed -i "s/\$(kafka_port)/${KAFKA_PORT}/g" ${SysConfig}

KAFKA10="${KAFKA10:-kafka10}"
sed -i "s/\$(kafka10)/${KAFKA10}/g" ${SysConfig}
KAFKA10_PORT="${KAFKA10_PORT:-9092}"
sed -i "s/\$(kafka10_port)/${KAFKA10_PORT}/g" ${SysConfig}

GROUP_EVENT_TOPIC1_SERVER="${GROUP_EVENT_TOPIC1_SERVER:-${CACHED_REDIS}}"
sed -i "s/\$(group_event_topic1_server)/${GROUP_EVENT_TOPIC1_SERVER}/g" ${SysConfig}
GROUP_EVENT_TOPIC1_PORT="${GROUP_EVENT_TOPIC1_PORT:-${CACHED_REDIS_PORT}}"
sed -i "s/\$(group_event_topic1_port)/${GROUP_EVENT_TOPIC1_PORT}/g" ${SysConfig}

GROUP_EVENT_TOPIC2_SERVER="${GROUP_EVENT_TOPIC2_SERVER:-${CACHED_REDIS}}"
sed -i "s/\$(group_event_topic2_server)/${GROUP_EVENT_TOPIC2_SERVER}/g" ${SysConfig}
GROUP_EVENT_TOPIC2_PORT="${GROUP_EVENT_TOPIC2_PORT:-${CACHED_REDIS_PORT}}"
sed -i "s/\$(group_event_topic2_port)/${GROUP_EVENT_TOPIC2_PORT}/g" ${SysConfig}

LOG_REDIS_SERVER="${LOG_REDIS_SERVER:-${CACHED_REDIS}}"
sed -i "s/\$(log_redis_server)/${LOG_REDIS_SERVER}/g" ${SysConfig}
LOG_REDIS_PORT="${LOG_REDIS_PORT:-${CACHED_REDIS_PORT}}"
sed -i "s/\$(log_redis_port)/${LOG_REDIS_PORT}/g" ${SysConfig}
LOG_REDIS_POOL_SIZE="${LOG_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(log_redis_pool_size)/${LOG_REDIS_POOL_SIZE}/g" ${SysConfig}

SSDB_BODY_REDIS_SERVER="${SSDB_BODY_REDIS_SERVER:-${PERSISTENT_REDIS}}"
sed -i "s/\$(ssdb_body_redis_server)/${SSDB_BODY_REDIS_SERVER}/g" ${SysConfig}
SSDB_BODY_REDIS_PORT="${SSDB_BODY_REDIS_PORT:-${PERSISTENT_REDIS_PORT}}"
sed -i "s/\$(ssdb_body_redis_port)/${SSDB_BODY_REDIS_PORT}/g" ${SysConfig}
SSDB_BODY_REDIS_POOL_SIZE="${SSDB_BODY_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(ssdb_body_redis_pool_size)/${SSDB_BODY_REDIS_POOL_SIZE}/g" ${SysConfig}

INDEX_REDIS_SERVER="${INDEX_REDIS_SERVER:-${PERSISTENT_REDIS}}"
sed -i "s/\$(index_redis_server)/${INDEX_REDIS_SERVER}/g" ${SysConfig}
INDEX_REDIS_PORT="${INDEX_REDIS_PORT:-${PERSISTENT_REDIS_PORT}}"
sed -i "s/\$(index_redis_port)/${INDEX_REDIS_PORT}/g" ${SysConfig}
INDEX_REDIS_POOL_SIZE="${INDEX_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(index_redis_pool_size)/${INDEX_REDIS_POOL_SIZE}/g" ${SysConfig}

RESOURCE_REDIS_SERVER="${RESOURCE_REDIS_SERVER:-${PERSISTENT_REDIS}}"
sed -i "s/\$(resource_redis_server)/${RESOURCE_REDIS_SERVER}/g" ${SysConfig}
RESOURCE_REDIS_PORT="${RESOURCE_REDIS_PORT:-${PERSISTENT_REDIS_PORT}}"
sed -i "s/\$(resource_redis_port)/${RESOURCE_REDIS_PORT}/g" ${SysConfig}
RESOURCE_REDIS_POOL_SIZE="${RESOURCE_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(resource_redis_pool_size)/${RESOURCE_REDIS_POOL_SIZE}/g" ${SysConfig}

BODY_REDIS_SERVER="${BODY_REDIS_SERVER:-${CACHED_REDIS}}"
sed -i "s/\$(body_redis_server)/${BODY_REDIS_SERVER}/g" ${SysConfig}
BODY_REDIS_PORT="${BODY_REDIS_PORT:-${CACHED_REDIS_PORT}}"
sed -i "s/\$(body_redis_port)/${BODY_REDIS_PORT}/g" ${SysConfig}
BODY_REDIS_POOL_SIZE="${BODY_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(body_redis_pool_size)/${BODY_REDIS_POOL_SIZE}/g" ${SysConfig}

ROSTER_REDIS_SERVER="${ROSTER_REDIS_SERVER:-${CACHED_REDIS}}"
sed -i "s/\$(roster_redis_server)/${ROSTER_REDIS_SERVER}/g" ${SysConfig}
ROSTER_REDIS_PORT="${ROSTER_REDIS_PORT:-${CACHED_REDIS_PORT}}"
sed -i "s/\$(roster_redis_port)/${ROSTER_REDIS_PORT}/g" ${SysConfig}
ROSTER_REDIS_POOL_SIZE="${ROSTER_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(roster_redis_pool_size)/${ROSTER_REDIS_POOL_SIZE}/g" ${SysConfig}

KAFKA_LOG_REDIS_SERVER="${KAFKA_LOG_REDIS_SERVER:-${CACHED_REDIS}}"
sed -i "s/\$(kafka_log_redis_server)/${KAFKA_LOG_REDIS_SERVER}/g" ${SysConfig}
KAFKA_LOG_REDIS_PORT="${KAFKA_LOG_REDIS_PORT:-${CACHED_REDIS_PORT}}"
sed -i "s/\$(kafka_log_redis_port)/${KAFKA_LOG_REDIS_PORT}/g" ${SysConfig}
KAFKA_LOG_REDIS_POOL_SIZE="${KAFKA_LOG_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(kafka_log_redis_pool_size)/${KAFKA_LOG_REDIS_POOL_SIZE}/g" ${SysConfig}

APPCONFIG_REDIS_SERVER="${APPCONFIG_REDIS_SERVER:-${PERSISTENT_REDIS}}"
sed -i "s/\$(appconfig_redis_server)/${APPCONFIG_REDIS_SERVER}/g" ${SysConfig}
APPCONFIG_REDIS_PORT="${APPCONFIG_REDIS_PORT:-${PERSISTENT_REDIS_PORT}}"
sed -i "s/\$(appconfig_redis_port)/${APPCONFIG_REDIS_PORT}/g" ${SysConfig}
APPCONFIG_REDIS_POOL_SIZE="${APPCONFIG_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(appconfig_redis_pool_size)/${APPCONFIG_REDIS_POOL_SIZE}/g" ${SysConfig}

MUC_REDIS_SERVER="${MUC_REDIS_SERVER:-${PERSISTENT_REDIS}}"
sed -i "s/\$(muc_redis_server)/${MUC_REDIS_SERVER}/g" ${SysConfig}
MUC_REDIS_PORT="${MUC_REDIS_PORT:-${PERSISTENT_REDIS_PORT}}"
sed -i "s/\$(muc_redis_port)/${MUC_REDIS_PORT}/g" ${SysConfig}
MUC_REDIS_POOL_SIZE="${MUC_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(muc_redis_pool_size)/${MUC_REDIS_POOL_SIZE}/g" ${SysConfig}

PRIVACY_REDIS_SERVER="${PRIVACY_REDIS_SERVER:-${PERSISTENT_REDIS}}"
sed -i "s/\$(privacy_redis_server)/${PRIVACY_REDIS_SERVER}/g" ${SysConfig}
PRIVACY_REDIS_PORT="${PRIVACY_REDIS_PORT:-${PERSISTENT_REDIS_PORT}}"
sed -i "s/\$(privacy_redis_port)/${PRIVACY_REDIS_PORT}/g" ${SysConfig}
PRIVACY_REDIS_POOL_SIZE="${PRIVACY_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(privacy_redis_pool_size)/${PRIVACY_REDIS_POOL_SIZE}/g" ${SysConfig}

CODIS_SESSION_REDIS_SERVER="${CODIS_SESSION_REDIS_SERVER:-${PERSISTENT_REDIS}}"
sed -i "s/\$(codis_session_redis_server)/${CODIS_SESSION_REDIS_SERVER}/g" ${SysConfig}
CODIS_SESSION_REDIS_PORT="${CODIS_SESSION_REDIS_PORT:-${PERSISTENT_REDIS_PORT}}"
sed -i "s/\$(codis_session_redis_port)/${CODIS_SESSION_REDIS_PORT}/g" ${SysConfig}
CODIS_SESSION_REDIS_POOL_SIZE="${CODIS_SESSION_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(codis_session_redis_pool_size)/${CODIS_SESSION_REDIS_POOL_SIZE}/g" ${SysConfig}

GROUP_MSG_REDIS_SERVER="${GROUP_MSG_REDIS_SERVER:-${PERSISTENT_REDIS}}"
sed -i "s/\$(group_msg_redis_server)/${GROUP_MSG_REDIS_SERVER}/g" ${SysConfig}
GROUP_MSG_REDIS_PORT="${GROUP_MSG_REDIS_PORT:-${PERSISTENT_REDIS_PORT}}"
sed -i "s/\$(group_msg_redis_port)/${GROUP_MSG_REDIS_PORT}/g" ${SysConfig}
GROUP_MSG_REDIS_POOL_SIZE="${GROUP_MSG_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(group_msg_redis_pool_size)/${GROUP_MSG_REDIS_POOL_SIZE}/g" ${SysConfig}

UNIQUE_MSG_REDIS_SERVER="${UNIQUE_MSG_REDIS_SERVER:-${CACHED_REDIS}}"
sed -i "s/\$(unique_msg_redis_server)/${UNIQUE_MSG_REDIS_SERVER}/g" ${SysConfig}
UNIQUE_MSG_REDIS_PORT="${UNIQUE_MSG_REDIS_PORT:-${CACHED_REDIS_PORT}}"
sed -i "s/\$(unique_msg_redis_port)/${UNIQUE_MSG_REDIS_PORT}/g" ${SysConfig}
UNIQUE_MSG_REDIS_POOL_SIZE="${UNIQUE_MSG_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(unique_msg_redis_pool_size)/${UNIQUE_MSG_REDIS_POOL_SIZE}/g" ${SysConfig}

MESSAGE_LIMIT_QUEUE_REDIS_SERVER="${MESSAGE_LIMIT_QUEUE_REDIS_SERVER:-${PERSISTENT_REDIS}}"
sed -i "s/\$(message_limit_queue_redis_server)/${MESSAGE_LIMIT_QUEUE_REDIS_SERVER}/g" ${SysConfig}
MESSAGE_LIMIT_QUEUE_REDIS_PORT="${MESSAGE_LIMIT_QUEUE_REDIS_PORT:-${PERSISTENT_REDIS_PORT}}"
sed -i "s/\$(message_limit_queue_redis_port)/${MESSAGE_LIMIT_QUEUE_REDIS_PORT}/g" ${SysConfig}
MESSAGE_LIMIT_QUEUE_REDIS_POOL_SIZE="${MESSAGE_LIMIT_QUEUE_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(message_limit_queue_redis_pool_size)/${MESSAGE_LIMIT_QUEUE_REDIS_POOL_SIZE}/g" ${SysConfig}

APNS_MUTE_REDIS_SERVER="${APNS_MUTE_REDIS_SERVER:-${PERSISTENT_REDIS}}"
sed -i "s/\$(apns_mute_redis_server)/${APNS_MUTE_REDIS_SERVER}/g" ${SysConfig}
APNS_MUTE_REDIS_PORT="${APNS_MUTE_REDIS_PORT:-${PERSISTENT_REDIS_PORT}}"
sed -i "s/\$(apns_mute_redis_port)/${APNS_MUTE_REDIS_PORT}/g" ${SysConfig}
APNS_MUTE_REDIS_POOL_SIZE="${APNS_MUTE_REDIS_POOL_SIZE:-50}"
sed -i "s/\$(apns_mute_redis_pool_size)/${APNS_MUTE_REDIS_POOL_SIZE}/g" ${SysConfig}

ETCD_SERVER_ADDRESS="${ETCD_SERVER_ADDRESS:-""}"
sed -i "s/\$(etcd_server_address)/${ETCD_SERVER_ADDRESS}/g" ${SysConfig}
ENABLE_ETCD_SERVICE_DISC="${ENABLE_ETCD_SERVICE_DISC:-false}"
sed -i "s/\$(enable_etcd_service_disc)/${ENABLE_ETCD_SERVICE_DISC}/g" ${SysConfig}
ENABLE_ETCD_CONFIG="${ENABLE_ETCD_CONFIG:-false}"
sed -i "s/\$(enable_etcd_config)/${ENABLE_ETCD_CONFIG}/g" ${SysConfig}

MYSQL="${MYSQL:-mysql}"
sed -i "s/\$(mysql)/${MYSQL}/g" ${SysConfig}
MYSQL_USERNAME="${MYSQL_USERNAME:-mysql}"
sed -i "s/\$(mysql_username)/${MYSQL_USERNAME}/g" ${SysConfig}
MYSQL_PASSWORD="${MYSQL_PASSWORD:-123456}"
sed -i "s/\$(mysql_password)/${MYSQL_PASSWORD}/g" ${SysConfig}

FULL_LARGE_GROUP="${FULL_LARGE_GROUP:-true}"
sed -i "s/\$(full_large_group)/${FULL_LARGE_GROUP}/g" ${SysConfig}
READ_GROUP_CURSOR="${READ_GROUP_CURSOR:-true}"
sed -i "s/\$(read_group_cursor)/${READ_GROUP_CURSOR}/g" ${SysConfig}
READ_GROUP_INDEX="${READ_GROUP_INDEX:-false}"
sed -i "s/\$(read_group_index)/${READ_GROUP_INDEX}/g" ${SysConfig}

APP_CONFIG_PARAM_LIST="${APP_CONFIG_PARAM_LIST:-[]}"
sed -i "s/\$(app_config_param_list)/${APP_CONFIG_PARAM_LIST}/g" ${SysConfig}

IM_LOG_PATH="${IM_LOG_PATH:-\/data\/apps\/opt\/msync\/log\/${POD_IP}}"
sed -i "s/\$(im_log_path)/${IM_LOG_PATH}/g" ${SysConfig}

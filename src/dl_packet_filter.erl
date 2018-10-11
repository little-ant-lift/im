-module(dl_packet_filter).
-export([check/3, check_ack/3]).
-include("pb_messagebody.hrl").
-include("logger.hrl").
check(From, To, Meta) ->
    lists:foreach(
      fun(Fun) ->
              Fun(From, To, Meta)
      end,
      [
       fun log_kafka_dl/3,
       fun inc_metrics_counter_dl/3
      ]).
check_ack(From, To, Meta) ->
    lists:foreach(
      fun(Fun) ->
              Fun(From, To, Meta)
      end,
      [
       fun log_kafka_dl_ack/3,
       fun inc_metrics_counter_dl_ack/3
      ]).

log_kafka_dl(From, To, Meta) ->
    msync_log:on_message_incoming(From, To, Meta, []).

log_kafka_dl_ack(From, To, Id) ->
    %%revert From/To, means To send ack for message from From
    msync_log:on_message_ack(To, From, Id, []).

inc_metrics_counter_dl(_From, _To, Meta) ->
    easemob_metrics_statistic:observe_summary(sp_size_sum, get_meta_size(Meta)),
    easemob_metrics_statistic:inc_counter(incoming).

inc_metrics_counter_dl_ack(_From, _To, Meta) ->
    easemob_metrics_statistic:inc_counter(ack).

get_meta_size(Meta) ->
    MetaBin = msync_msg:encode_meta(Meta),
    byte_size(MetaBin).


%%%-------------------------------------------------------------------
%%% @author WangChunye <wcy123@gmail.com>
%%% @copyright (C) 2015, WangChunye
%%% @doc
%%%
%%% @end
%%% Created : 27 Sep 2015 by WangChunye <wcy123@gmail.com>
%%%-------------------------------------------------------------------
-module(msync_privacy_cache).
-include("logger.hrl").
-author("wcy123@gmail.com").

-include("jlib.hrl").
-include("pb_jid.hrl").
-include("mod_privacy.hrl").
%% simplified interface for MSYNC
-export(
   [
    %% return a list of JID:s of a JID
    read/1,
    %% add a list of new JID:s into the blacklist of a JID
    add/2,
    %% is a member in the privacy list
    member/2,
    %% remove member from the black list
    remove/2,
    %% clear the privacy list
    clear/1
   ]).


read(#'JID'{}=JID) ->
    Privacy = read_privacy(#'JID'{}=JID),
    convert_from_privacy(Privacy).

convert_from_privacy(not_found) ->
    [];
convert_from_privacy(#privacy{default = Default, lists = PropList}) ->
    List = proplists:get_value(Default, PropList,[]),
    lists:filtermap(fun convert_from_list_item/1, List).

convert_from_list_item(#listitem{type=jid, action = deny, value = {U,S,_R}}) ->
    [AppKey, Name] = binary:split(U,<<"_">>),
    {true, #'JID'{ app_key = AppKey,
                   name = Name,
                   domain = S,
                   %% ignore resource
                   client_resource = undefined }};
convert_from_list_item(_) ->
    false.


add(#'JID'{}=JID, List)
  when is_list(List) ->
    Privacy = read_privacy(#'JID'{}=JID),
    OldJIDList = convert_from_privacy(Privacy),

    NewJIDList =
        sets:to_list(
          sets:from_list(
            lists:map(
              fun(J) ->
                      J#'JID'{client_resource = undefined}
              end, List) ++ OldJIDList)),
    NewListItems = lists:map(fun convert_to_list_item/1, NewJIDList),
    NewPrivacy = case Privacy of
                     not_found -> #privacy{default = ?DEFAULT_PRIVACY};
                     _ -> Privacy
                 end,
    NewPrivacy2 = convert_to_privacy(NewPrivacy, NewListItems),
    write_privacy(JID, NewPrivacy2).

remove(#'JID'{}=JID, List)
  when is_list(List) ->
    List2 =
        lists:map(
          fun(J) ->
                  J#'JID'{client_resource = undefined}
          end, List),
    Privacy = read_privacy(#'JID'{}=JID),
    OldJIDList = convert_from_privacy(Privacy),

    NewJIDList =
        lists:filter(
          fun(J) ->
                  not lists:member(J#'JID'{client_resource = undefined}, List2)
          end,  OldJIDList),
    NewListItems = lists:map(fun convert_to_list_item/1, NewJIDList),
    NewPrivacy = case Privacy of
                     not_found -> #privacy{default = ?DEFAULT_PRIVACY};
                     _ -> Privacy
                 end,
    NewPrivacy2 = convert_to_privacy(NewPrivacy, NewListItems),
    write_privacy(JID, NewPrivacy2).


convert_to_privacy(#privacy{} = Privacy, ListItems) ->
    Privacy#privacy{
      lists = set_order(ListItems)
     }.


set_order(ListItems) ->
    [ Item#listitem{ order = Order }
      ||
        {Item, Order} <-
            lists:zip(ListItems, lists:seq(1, erlang:length(ListItems)))
    ].


convert_to_list_item(#'JID'{domain = S, client_resource = Resource} = JID)  ->
    U = msync_msg:pb_jid_to_long_username(JID),
    R = msync_msg:get_with_default(Resource, <<>>),
    #listitem{type = jid,
              value = { U,S,R },
              action = deny,order = 2,
              match_all = true,
              match_iq = false,
              match_message = false,
              match_presence_in = false,
              match_presence_out = false }.


member(#'JID'{} = Owner, #'JID'{} = Other) ->
    ?DEBUG("Owner = ~p, Other = ~p", [Owner, Other]),
    lists:member(Other#'JID'{client_resource = undefined },
                 read(Owner)).

clear(#'JID'{} = JID) ->
    LUser = msync_msg:pb_jid_to_long_username(JID),
    Domain = JID#'JID'.domain,
    easemob_privacy:remove_privacy(LUser, Domain).

%% internal functions
read_privacy(#'JID'{}=JID) ->
    LUser = msync_msg:pb_jid_to_long_username(JID),
    Domain = JID#'JID'.domain,
    Privacy = easemob_privacy:read_privacy(LUser, Domain),
    Privacy.
write_privacy(#'JID'{}=JID, Privacy) ->
    LUser = msync_msg:pb_jid_to_long_username(JID),
    Domain = JID#'JID'.domain,
    easemob_privacy:write_privacy(LUser, Domain, Privacy#privacy.lists).

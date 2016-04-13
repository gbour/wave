%%
%%    Wave - MQTT Broker
%%    Copyright (C) 2014-2016 - Guillaume Bour
%%
%%    This program is free software: you can redistribute it and/or modify
%%    it under the terms of the GNU Affero General Public License as published
%%    by the Free Software Foundation, version 3 of the License.
%%
%%    This program is distributed in the hope that it will be useful,
%%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%    GNU Affero General Public License for more details.
%%
%%    You should have received a copy of the GNU Affero General Public License
%%    along with this program.  If not, see <http://www.gnu.org/licenses/>.

%%
%% NOTE: current implementation is really naive
%%       we have to go through the whole list to match each subscriber topic regex
%%       will be really slow w/ hundred thousand subscribers !
%%
-module(mqtt_offline).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).

-include("mqtt_msg.hrl").

-record(state, {
    registrations = []
}).

%
%-export([get/1, subscribe/2, get_subscribers/1]).
-export([register/3, recover/1, flush/2, dump/0, event/3]).
% gen_server API
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

init(_) ->
    {ok, #state{}}.

%%
%% PUBLIC API
%%

%
% todo: there may be wildcard in topic name => need to do a search
%w
%unsubscribe(Subscriber) ->
%    gen_server:call(?MODULE, {unsubscribe, Subscriber}).
-spec register(binary(), integer(), binary()) -> ok.
register(Topic, Qos, DeviceID) ->
    gen_server:call(?MODULE, {register, Topic, Qos, DeviceID}).


-spec recover(binary()) -> list({Topic:: binary(), Qos :: integer()}).
recover(DeviceID) ->
    gen_server:call(?MODULE, {recover, DeviceID}).

-spec flush(binary(), mqtt_topic_registry:subscriber()) -> ok.
flush(DeviceID, Session) ->
    gen_server:cast(?MODULE, {flush, DeviceID, Session}).

-spec dump() -> ok.
dump() ->
    gen_server:call(?MODULE,dump).

-spec event(pid(), binary(), binary()) -> ok.
event(_Pid, Topic, Content) ->
    gen_server:call(?MODULE, {event, Topic, Content}).

%%
%% PRIVATE API
%%

handle_call(dump, _, State=#state{registrations=R}) ->
    lager:info("~p", [R]),
    {reply, ok, State};

handle_call({register, Topic, Qos, DeviceID}, _, State=#state{registrations=R}) ->
    mqtt_topic_registry:subscribe(Topic, Qos, {?MODULE, event, self()}),

    {reply, ok, State#state{registrations=[{Topic, Qos, DeviceID}|R]}};

handle_call({recover, DeviceID}, _, State=#state{registrations=R}) ->
    {R2, DTopics} = lists:partition(fun({_Topic, _Qos, DeviceID2}) -> DeviceID2 =/= DeviceID end, R),
    lager:info("~p / ~p", [R2, DTopics]),
    DTopics2 = lists:map(fun({Topic, Qos, _DeviceID}) ->
            mqtt_topic_registry:unsubscribe(Topic, {?MODULE,event,self()}),

            {Topic, Qos}
        end,
        DTopics
    ),

    {reply, DTopics2, State#state{registrations=R2}};

%TODO: add MatchTopic in parameters
%      ie the matching topic rx that lead to executing this callback
handle_call({event, {Topic,TopicMatch}, Content}, _, State=#state{registrations=R}) ->
    lager:info("received event on ~p (matched with ~s)", [Topic, TopicMatch]),

    %TODO: optimisation: for messages shorted than len(HMAC),
    %      store directly the message in the queue
    MsgID = wave_utils:bin(hmac:hexlify(hmac:hmac("", Content))),
    Ret = wave_db:set({s, <<"msg:", MsgID/binary>>}, Content),
    lager:info("~p", [Ret]),

    [
        case T2 of
            TopicMatch ->
                wave_db:push(<<"queue:", DeviceID/binary>>, [Topic, MsgID]),
                wave_db:incr(<<"msg:", MsgID/binary, ":refcount">>);

            _     ->
                pass
        end

        || {T2, DeviceID} <- R
    ],

    {reply, ok, State};

handle_call(_,_,State) ->
    {reply, ok, State}.

handle_cast({flush, DeviceID, Device={_M,_F,_Pid}}, State) ->
    lager:info("flush ~p", [DeviceID]),

    {ok, MsgIDs} = wave_db:range(<<"queue:", DeviceID/binary>>),
    priv_flush(MsgIDs, Device),

    %TODO: delete queue item
    wave_db:del(<<"queue:",DeviceID/binary>>, length(MsgIDs)),

    {noreply, State};

handle_cast(_, State) ->
    {noreply, State}.


handle_info(_, State) ->
    {noreply, State}.


terminate(_,_) ->
    ok.


code_change(_, State, _) ->
    {ok, State}.

%%
%% PRIVATE FUNS
%%

% "unstore" & "emit" messages from db
%   - decrement message reference counter
%   - if counter is 0, deletes message content
%
% MsgIDs: lists of serialized topic+msgid
%           [topic1, msgid1, topic2, msgid2, ...]
%
-spec priv_flush(MsgIDs :: list(binary()), Device :: mqtt_topic_registry:subscriber()) -> ok.
priv_flush([], _) ->
    ok;
priv_flush([Topic, MsgID |T], Device={M,F,Pid}) ->
    {ok, Msg} = wave_db:get({s, <<"msg:", MsgID/binary>>}),
    lager:info("flush msg: ~p (id: ~p, topic= ~p)", [Msg, MsgID, Topic]),
    M:F(Pid, {Topic, undefined}, Msg),

    %TODO: operation must be atomic (including the LRANGE ?)
    %      use MULTI/EXEC
    {ok, Cnt} = wave_db:decr(<<"msg:", MsgID/binary,":refcount">>),
    Cnt2 = wave_utils:int(Cnt),
    if 
        Cnt2 =< 0 ->
            wave_db:del(<<"msg:", MsgID/binary>>),
            wave_db:del(<<"msg:", MsgID/binary, ":refcount">>);

        true ->
            ok
    end,

    % next queued message
    priv_flush(T, Device).


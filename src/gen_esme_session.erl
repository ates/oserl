%%% Copyright (C) 2009 Enrique Marcote, Miguel Rodriguez
%%% All rights reserved.
%%%
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are met:
%%%
%%% o Redistributions of source code must retain the above copyright notice,
%%%   this list of conditions and the following disclaimer.
%%%
%%% o Redistributions in binary form must reproduce the above copyright notice,
%%%   this list of conditions and the following disclaimer in the documentation
%%%   and/or other materials provided with the distribution.
%%%
%%% o Neither the name of ERLANG TRAINING AND CONSULTING nor the names of its
%%%   contributors may be used to endorse or promote products derived from this
%%%   software without specific prior written permission.
%%%
%%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
%%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
%%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
%%% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
%%% LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
%%% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
%%% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
%%% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
%%% CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
%%% ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
%%% POSSIBILITY OF SUCH DAMAGE.
-module(gen_esme_session).
-behaviour(gen_fsm).

%%% INCLUDE FILES
-include_lib("oserl/include/oserl.hrl").

%%% BEHAVIOUR EXPORTS
-export([behaviour_info/1]).

%%% START/STOP EXPORTS
-export([start_link/2, stop/1, stop/2]).

%%% SMPP EXPORTS
-export([bind_receiver/2,
         bind_transmitter/2,
         bind_transceiver/2,
         broadcast_sm/2,
         cancel_broadcast_sm/2,
         cancel_sm/2,
         data_sm/2,
         query_broadcast_sm/2,
         query_sm/2,
         replace_sm/2,
         submit_multi/2,
         submit_sm/2,
         unbind/1]).

%%% INIT/TERMINATE EXPORTS
-export([init/1, terminate/3]).

%%% ASYNC REQUEST EXPORTS
-export([bound_rx/2,
         bound_tx/2,
         bound_trx/2,
         listen/2,
         open/2,
         outbound/2,
         unbound/2]).

%%% HANDLE EXPORTS
-export([handle_event/3, handle_info/3, handle_sync_event/4]).

%%% CODE UPDATE EXPORTS
-export([code_change/4]).

%%% RECORDS
-record(st,
        {esme,
         mod,
         log,
         sequence_number = 0,
         sock,
         sock_ctrl,
         req_tab,
         congestion_state = 0,
         timers,
         session_init_timer,
         enquire_link_timer,
         inactivity_timer,
         enquire_link_resp_timer}).

%%%-----------------------------------------------------------------------------
%%% BEHAVIOUR EXPORTS
%%%-----------------------------------------------------------------------------
behaviour_info(callbacks) ->
    [{handle_accept, 2},
     {handle_alert_notification, 2},
     {handle_closed, 2},
     {handle_enquire_link, 2},
     {handle_operation, 2},
     {handle_outbind, 2},
     {handle_resp, 3},
     {handle_unbind, 2}];
behaviour_info(_Other) ->
    undefined.

%%%-----------------------------------------------------------------------------
%%% START/STOP EXPORTS
%%%-----------------------------------------------------------------------------
start_link(Mod, Opts) ->
    Esme = proplists:get_value(esme, Opts, self()),
    case proplists:get_value(lsock, Opts) of
        undefined ->
            start_connect(Mod, Esme, Opts);
        LSock ->
            start_listen(Mod, Esme, [{lsock, LSock} | Opts])
    end.


stop(FsmRef) ->
    stop(FsmRef, normal).

stop(FsmRef, Reason) ->
    gen_fsm:sync_send_all_state_event(FsmRef, {stop, Reason}, ?ASSERT_TIME).

%%%-----------------------------------------------------------------------------
%%% SMPP EXPORTS
%%%-----------------------------------------------------------------------------
bind_receiver(FsmRef, Params) ->
    Event = {?COMMAND_ID_BIND_RECEIVER, Params},
    gen_fsm:sync_send_all_state_event(FsmRef, Event, ?ASSERT_TIME).


bind_transmitter(FsmRef, Params) ->
    Event = {?COMMAND_ID_BIND_TRANSMITTER, Params},
    gen_fsm:sync_send_all_state_event(FsmRef, Event, ?ASSERT_TIME).


bind_transceiver(FsmRef, Params) ->
    Event = {?COMMAND_ID_BIND_TRANSCEIVER, Params},
    gen_fsm:sync_send_all_state_event(FsmRef, Event, ?ASSERT_TIME).


broadcast_sm(FsmRef, Params) ->
    Event = {?COMMAND_ID_BROADCAST_SM, Params},
    gen_fsm:sync_send_all_state_event(FsmRef, Event, ?ASSERT_TIME).


cancel_broadcast_sm(FsmRef, Params) ->
    Event = {?COMMAND_ID_CANCEL_BROADCAST_SM, Params},
    gen_fsm:sync_send_all_state_event(FsmRef, Event, ?ASSERT_TIME).


cancel_sm(FsmRef, Params) ->
    Event = {?COMMAND_ID_CANCEL_SM, Params},
    gen_fsm:sync_send_all_state_event(FsmRef, Event, ?ASSERT_TIME).


data_sm(FsmRef, Params) ->
    Event = {?COMMAND_ID_DATA_SM, Params},
    gen_fsm:sync_send_all_state_event(FsmRef, Event, ?ASSERT_TIME).


query_broadcast_sm(FsmRef, Params) ->
    Event = {?COMMAND_ID_QUERY_BROADCAST_SM, Params},
    gen_fsm:sync_send_all_state_event(FsmRef, Event, ?ASSERT_TIME).


query_sm(FsmRef, Params) ->
    Event = {?COMMAND_ID_QUERY_SM, Params},
    gen_fsm:sync_send_all_state_event(FsmRef, Event, ?ASSERT_TIME).


replace_sm(FsmRef, Params) ->
    Event = {?COMMAND_ID_REPLACE_SM, Params},
    gen_fsm:sync_send_all_state_event(FsmRef, Event, ?ASSERT_TIME).


submit_multi(FsmRef, Params) ->
    Event = {?COMMAND_ID_SUBMIT_MULTI, Params},
    gen_fsm:sync_send_all_state_event(FsmRef, Event, ?ASSERT_TIME).


submit_sm(FsmRef, Params) ->
    Event = {?COMMAND_ID_SUBMIT_SM, Params},
    gen_fsm:sync_send_all_state_event(FsmRef, Event, ?ASSERT_TIME).


unbind(FsmRef) ->
    Event = {?COMMAND_ID_UNBIND, []},
    gen_fsm:sync_send_all_state_event(FsmRef, Event, ?ASSERT_TIME).

%%%-----------------------------------------------------------------------------
%%% INIT/TERMINATE EXPORTS
%%%-----------------------------------------------------------------------------
init([Mod, Esme, Opts]) ->
    _Ref = erlang:monitor(process, Esme),
    Timers = proplists:get_value(timers, Opts, ?DEFAULT_TIMERS_SMPP),
    Log = proplists:get_value(log, Opts),
    case proplists:get_value(lsock, Opts) of
        undefined ->
            init_open(Mod, Esme, proplists:get_value(sock, Opts), Timers, Log);
        LSock ->
            init_listen(Mod, Esme, LSock, Timers, Log)
    end.

init_open(Mod, Esme, Sock, Tmr, Log) ->
    Self = self(),
    Pid = spawn_link(smpp_session, wait_recv, [Self, Sock, Log]),
    {ok, open, #st{esme = Esme,
                   mod = Mod,
                   log = Log,
                   sock = Sock,
                   sock_ctrl = Pid,
                   req_tab = smpp_req_tab:new(),
                   timers = Tmr,
                   session_init_timer = start_timer(Tmr, session_init_timer),
                   enquire_link_timer = start_timer(Tmr, enquire_link_timer)}}.


init_listen(Mod, Esme, LSock, Tmr, Log) ->
    Self = self(),
    Pid = spawn_link(smpp_session, wait_listen, [Self, LSock, Log]),
    {ok, listen, #st{esme = Esme,
                     mod = Mod,
                     log = Log,
                     sock_ctrl = Pid,
                     req_tab = smpp_req_tab:new(),
                     timers = Tmr}}.


terminate(Reason, _Stn, Std) ->
    unlink(Std#st.sock_ctrl),
    exit(Std#st.sock_ctrl, Reason),
    if Std#st.sock == undefined -> ok; true -> gen_tcp:close(Std#st.sock) end.

%%%-----------------------------------------------------------------------------
%%% ASYNC REQUEST EXPORTS
%%%-----------------------------------------------------------------------------
bound_rx({?COMMAND_ID_ALERT_NOTIFICATION, _Pdu} = R, St) ->
    handle_peer_alert_notification(R, St),
    {next_state, bound_rx, St};
bound_rx({CmdId, _Pdu} = R, St)
  when CmdId == ?COMMAND_ID_DATA_SM; CmdId == ?COMMAND_ID_DELIVER_SM ->
    handle_peer_operation(R, St),
    {next_state, bound_rx, St};
bound_rx({?COMMAND_ID_UNBIND, _Pdu} = R, St) ->
    case handle_peer_unbind(R, St) of  % Synchronous
        true ->
            cancel_timer(St#st.inactivity_timer),
            {next_state, unbound, St};
        false ->
            {next_state, bound_rx, St}
    end;
bound_rx({timeout, _Ref, Timer}, St) ->
    case handle_timeout(Timer, St) of
        ok ->
            {next_state, bound_rx, St};
        {error, Reason} ->
            {stop, Reason, St}
    end;
bound_rx(R, St) ->
    esme_rinvbndsts_resp(R, St#st.sock, St#st.log),
    {next_state, bound_rx, St}.


bound_tx({?COMMAND_ID_UNBIND, _Pdu} = R, St) ->
    case handle_peer_unbind(R, St) of  % Synchronous
        true ->
            cancel_timer(St#st.inactivity_timer),
            {next_state, unbound, St};
        false ->
            {next_state, bound_tx, St}
    end;
bound_tx({timeout, _Ref, Timer}, St) ->
    case handle_timeout(Timer, St) of
        ok ->
            {next_state, bound_tx, St};
        {error, Reason} ->
            {stop, Reason, St}
    end;
bound_tx(R, St) ->
    esme_rinvbndsts_resp(R, St#st.sock, St#st.log),
    {next_state, bound_tx, St}.


bound_trx({?COMMAND_ID_ALERT_NOTIFICATION, _Pdu} = R, St) ->
    handle_peer_alert_notification(R, St),
    {next_state, bound_trx, St};
bound_trx({CmdId, _Pdu} = R, St)
  when CmdId == ?COMMAND_ID_DATA_SM; CmdId == ?COMMAND_ID_DELIVER_SM ->
    handle_peer_operation(R, St),
    {next_state, bound_trx, St};
bound_trx({?COMMAND_ID_UNBIND, _Pdu} = R, St) ->
    case handle_peer_unbind(R, St) of  % Synchronous
        true ->
            cancel_timer(St#st.inactivity_timer),
            {next_state, unbound, St};
        false ->
            {next_state, bound_trx, St}
    end;
bound_trx({timeout, _Ref, Timer}, St) ->
    case handle_timeout(Timer, St) of
        ok ->
            {next_state, bound_trx, St};
        {error, Reason} ->
            {stop, Reason, St}
    end;
bound_trx(R, St) ->
    esme_rinvbndsts_resp(R, St#st.sock, St#st.log),
    {next_state, bound_trx, St}.


listen({accept, Sock, Addr}, St) ->
    case (St#st.mod):handle_accept(St#st.esme, Addr) of
        ok ->
            TI = start_timer(St#st.timers, session_init_timer),
            TE = start_timer(St#st.timers, enquire_link_timer),
            {next_state, open, St#st{sock = Sock,
                                     session_init_timer = TI,
                                     enquire_link_timer = TE}};
        {error, Reason} ->
            gen_tcp:close(Sock),
            {stop, Reason, St}
    end.


open({?COMMAND_ID_OUTBIND, _Pdu} = R, St) ->
    cancel_timer(St#st.session_init_timer),
    cancel_timer(St#st.enquire_link_timer),
    handle_peer_outbind(R, St),
    TE = start_timer(St#st.timers, enquire_link_timer),
    TS = start_timer(St#st.timers, session_init_timer),
    {next_state, outbound, St#st{enquire_link_timer = TE,
                                 session_init_timer = TS}};
open({timeout, _Ref, Timer}, St) ->
    case handle_timeout(Timer, St) of
        ok ->
            {next_state, open, St};
        {error, Reason} ->
            {stop, Reason, St}
    end;
open(R, St) ->
    esme_rinvbndsts_resp(R, St#st.sock, St#st.log),
    {next_state, open, St}.


outbound({timeout, _Ref, Timer}, St) ->
    case handle_timeout(Timer, St) of
        ok ->
            {next_state, outbound, St};
        {error, Reason} ->
            {stop, Reason, St}
    end;
outbound(R, St) ->
    esme_rinvbndsts_resp(R, St#st.sock, St#st.log),
    {next_state, outbound, St}.


unbound({timeout, _Ref, Timer}, St) ->
    case handle_timeout(Timer, St) of
        ok ->
            {next_state, unbound, St};
        {error, Reason} ->
            {stop, Reason, St}
    end;
unbound(R, St) ->
    esme_rinvbndsts_resp(R, St#st.sock, St#st.log),
    {next_state, unbound, St}.

%% Auxiliary function for Event/2 functions.
%%
%% Sends the corresponding response with a ``?ESME_RINVBNDSTS`` status.
esme_rinvbndsts_resp({CmdId, Pdu}, Sock, Log) ->
    SeqNum = smpp_operation:get_value(sequence_number, Pdu),
    case ?VALID_COMMAND_ID(CmdId) of
        true ->
            RespId = ?RESPONSE(CmdId),
            send_response(RespId, ?ESME_RINVBNDSTS, SeqNum, [], Sock, Log);
        false ->
            RespId = ?COMMAND_ID_GENERIC_NACK,
            send_response(RespId, ?ESME_RINVCMDID, SeqNum, [], Sock, Log)
    end.

%%%-----------------------------------------------------------------------------
%%% HANDLE EXPORTS
%%%-----------------------------------------------------------------------------
handle_event({input, CmdId, _Pdu, _Lapse, _Timestamp}, Stn, Std)
  when CmdId == ?COMMAND_ID_ENQUIRE_LINK_RESP ->
    cancel_timer(Std#st.enquire_link_resp_timer),
    {next_state, Stn, Std};
handle_event({input, CmdId, Pdu, _Lapse, _Timestamp}, Stn, Std)
  when CmdId == ?COMMAND_ID_GENERIC_NACK ->
    cancel_timer(Std#st.enquire_link_resp_timer),  % In case it was set
    SeqNum = smpp_operation:get_value(sequence_number, Pdu),
    case smpp_req_tab:read(Std#st.req_tab, SeqNum) of
        {ok, {SeqNum, _ReqId, RTimer, Ref}} ->
            cancel_timer(RTimer),
            Status = case smpp_operation:get_value(command_status, Pdu) of
                         ?ESME_ROK -> % Some MCs return ESME_ROK in generic_nack
                             ?ESME_RINVCMDID;
                         Other ->
                             Other
                     end,
            handle_peer_resp({error, {command_status, Status}}, Ref, Std);
        {error, not_found} ->
            % Do not send anything, might enter a request/response loop
            true
    end,
    {next_state, Stn, Std};
handle_event({input, CmdId, Pdu, _Lapse, _Timestamp}, Stn, Std)
  when ?IS_RESPONSE(CmdId) ->
    cancel_timer(Std#st.enquire_link_resp_timer),  % In case it was set
    SeqNum = smpp_operation:get_value(sequence_number, Pdu),
    ReqId = ?REQUEST(CmdId),
    case smpp_req_tab:read(Std#st.req_tab, SeqNum) of
        {ok, {SeqNum, ReqId, RTimer, Ref}} ->
            cancel_timer(RTimer),
            case smpp_operation:get_value(command_status, Pdu) of
                ?ESME_ROK when CmdId == ?COMMAND_ID_BIND_RECEIVER_RESP ->
                    cancel_timer(Std#st.session_init_timer),
                    handle_peer_resp({ok, Pdu}, Ref, Std),
                    {next_state, bound_rx, Std};
                ?ESME_ROK when CmdId == ?COMMAND_ID_BIND_TRANSCEIVER_RESP ->
                    cancel_timer(Std#st.session_init_timer),
                    handle_peer_resp({ok, Pdu}, Ref, Std),
                    {next_state, bound_trx, Std};
                ?ESME_ROK when CmdId == ?COMMAND_ID_BIND_TRANSMITTER_RESP ->
                    cancel_timer(Std#st.session_init_timer),
                    handle_peer_resp({ok, Pdu}, Ref, Std),
                    {next_state, bound_tx, Std};
                ?ESME_ROK when CmdId == ?COMMAND_ID_UNBIND_RESP ->
                    cancel_timer(Std#st.inactivity_timer),
                    handle_peer_resp({ok, Pdu}, Ref, Std),
                    {next_state, unbound, Std};
                ?ESME_ROK ->
                    handle_peer_resp({ok, Pdu}, Ref, Std),
                    {next_state, Stn, Std};
                Status ->
                    Reason = {command_status, Status},
                    handle_peer_resp({error, Reason}, Ref, Std),
                    {next_state, Stn, Std}
            end;
        {error, not_found} ->
            Sock = Std#st.sock,
            Log = Std#st.log,
            Nack = ?COMMAND_ID_GENERIC_NACK,
            send_response(Nack, ?ESME_RINVCMDID, SeqNum, [], Sock, Log),
            {next_state, Stn, Std}
    end;
handle_event({input, CmdId, Pdu, _Lapse, _Timestamp}, Stn, Std)
  when CmdId == ?COMMAND_ID_ENQUIRE_LINK ->
    cancel_timer(Std#st.enquire_link_resp_timer),  % In case it was set
    cancel_timer(Std#st.enquire_link_timer),
    ok = (Std#st.mod):handle_enquire_link(Std#st.esme, Pdu),
    SeqNum = smpp_operation:get_value(sequence_number, Pdu),
    RespId = ?COMMAND_ID_ENQUIRE_LINK_RESP,
    send_response(RespId, ?ESME_ROK, SeqNum, [], Std#st.sock, Std#st.log),
    T = start_timer(Std#st.timers, enquire_link_timer),
    {next_state, Stn, Std#st{enquire_link_timer = T}};
handle_event({input, CmdId, Pdu, Lapse, Timestamp}, Stn, Std) ->
    cancel_timer(Std#st.enquire_link_resp_timer),  % In case it was set
    cancel_timer(Std#st.inactivity_timer),
    cancel_timer(Std#st.enquire_link_timer),
    gen_fsm:send_event(self(), {CmdId, Pdu}),
    TE = start_timer(Std#st.timers, enquire_link_timer),
    TI = start_timer(Std#st.timers, inactivity_timer),
    C = smpp_session:congestion(Std#st.congestion_state, Lapse, Timestamp),
    {next_state, Stn, Std#st{congestion_state = C,
                             enquire_link_timer = TE,
                             inactivity_timer = TI}};
handle_event({error, CmdId, Status, _SeqNum}, _Stn, Std)
  when ?IS_RESPONSE(CmdId) ->
    {stop, {command_status, Status}, Std};
handle_event({error, CmdId, Status, SeqNum}, Stn, Std) ->
    RespId = case ?VALID_COMMAND_ID(CmdId) of
                 true when CmdId /= ?COMMAND_ID_GENERIC_NACK ->
                     ?RESPONSE(CmdId);
                 _Otherwise ->
                     ?COMMAND_ID_GENERIC_NACK
             end,
    send_response(RespId, Status, SeqNum,[], Std#st.sock, Std#st.log),
    {next_state, Stn, Std};
handle_event(?COMMAND_ID_ENQUIRE_LINK, Stn, Std) ->
    NewStd = send_enquire_link(Std),
    {next_state, Stn, NewStd};
handle_event({sock_error, _Reason}, unbound, Std) ->
    gen_tcp:close(Std#st.sock),
    {stop, normal, Std#st{sock = undefined}};
handle_event({sock_error, Reason}, _Stn, Std) ->
    gen_tcp:close(Std#st.sock),
    (Std#st.mod):handle_closed(Std#st.esme, Reason),
    {stop, normal, Std#st{sock = undefined}};
handle_event({listen_error, Reason}, _Stn, Std) ->
    {stop, Reason, Std}.


handle_info({'DOWN', _Ref, _Type, _Esme, Reason}, _Stn, Std) ->
    {stop, Reason, Std};
handle_info(_Info, Stn, Std) ->
    {next_state, Stn, Std}.


handle_sync_event({stop, Reason}, _From, _Stn, Std) ->
    {stop, Reason, ok, Std};
handle_sync_event({CmdId, Params}, From, Stn, Std) ->
    NewStd = send_request(CmdId, Params, From, Std),
    {next_state, Stn, NewStd}.

%%%-----------------------------------------------------------------------------
%%% CODE UPDATE EXPORTS
%%%-----------------------------------------------------------------------------
code_change(_OldVsn, Stn, Std, _Extra) ->
    {ok, Stn, Std}.

%%%-----------------------------------------------------------------------------
%%% START FUNCTIONS
%%%-----------------------------------------------------------------------------
start_connect(Mod, Esme, Opts) ->
    case smpp_session:connect(Opts) of
        {ok, Sock} ->
            Args = [Mod, Esme, [{sock, Sock} | Opts]],
            case gen_fsm:start_link(?MODULE, Args, []) of
                {ok, Pid} ->
                    case gen_tcp:controlling_process(Sock, Pid) of
                        ok ->
                            {ok, Pid};
                        _CtrlError ->
                            % Session started but could not assign the socket
                            % to it, most probably because it is closed.
                            % Close it to make sure and force handle_closed.
                            %
                            % If we return an error here, we will be having
                            % an unexpected handle_closed call later.
                            gen_tcp:close(Sock),
                            {ok, Pid}
                    end;
                SessionError ->
                    gen_tcp:close(Sock),
                    SessionError
            end;
        ConnError ->
            ConnError
    end.

start_listen(Mod, Esme, Opts) ->
    gen_fsm:start_link(?MODULE, [Mod, Esme, Opts], []).

%%%-----------------------------------------------------------------------------
%%% HANDLE PEER FUNCTIONS
%%%-----------------------------------------------------------------------------
handle_peer_alert_notification({?COMMAND_ID_ALERT_NOTIFICATION, Pdu}, St)->
    (St#st.mod):handle_alert_notification(St#st.esme, Pdu).


handle_peer_operation({CmdId, Pdu}, St) ->
    CmdName = ?COMMAND_NAME(CmdId),
    SeqNum = smpp_operation:get_value(sequence_number, Pdu),
    RespId = ?RESPONSE(CmdId),
    Sock = St#st.sock,
    Log = St#st.log,
    case (St#st.mod):handle_operation(St#st.esme, {CmdName, Pdu}) of
        {ok, PList1} ->
            PList2  = [{congestion_state, St#st.congestion_state}],
            Params = smpp_operation:merge(PList1, PList2),
            send_response(RespId, ?ESME_ROK, SeqNum, Params, Sock, Log),
            true;
        {error, Error} ->
            send_response(RespId, Error, SeqNum, [], Sock, Log),
            false
    end.


handle_peer_outbind({?COMMAND_ID_OUTBIND, Pdu}, St) ->
    (St#st.mod):handle_outbind(St#st.esme, Pdu).


handle_peer_resp(Reply, Ref, St) ->
    (St#st.mod):handle_resp(St#st.esme, Reply, Ref).


handle_peer_unbind({?COMMAND_ID_UNBIND, Pdu}, St) ->
    SeqNum = smpp_operation:get_value(sequence_number, Pdu),
    RespId = ?COMMAND_ID_UNBIND_RESP,
    case (St#st.mod):handle_unbind(St#st.esme, Pdu) of
        ok ->
            send_response(RespId, ?ESME_ROK, SeqNum, [], St#st.sock, St#st.log),
            true;
        {error, Error} ->
            send_response(RespId, Error, SeqNum, [],  St#st.sock, St#st.log),
            false
    end.

%%%-----------------------------------------------------------------------------
%%% TIMER FUNCTIONS
%%%-----------------------------------------------------------------------------
cancel_timer(undefined) ->
    false;
cancel_timer(Ref) ->
    gen_fsm:cancel_timer(Ref).


handle_timeout({response_timer, SeqNum}, St) ->
    {ok, {SeqNum, CmdId, _, Ref}} = smpp_req_tab:read(St#st.req_tab, SeqNum),
    Status = smpp_operation:request_failure_code(CmdId),
    handle_peer_resp({error, {command_status, Status}}, Ref, St),
    ok;
handle_timeout(enquire_link_timer, _St) ->
    ok = gen_fsm:send_all_state_event(self(), ?COMMAND_ID_ENQUIRE_LINK);
handle_timeout(enquire_link_failure, _St) ->
    {error, {timeout, enquire_link}};
handle_timeout(session_init_timer, _St) ->
    {error, {timeout, session_init_timer}};
handle_timeout(inactivity_timer, _St) ->
    {error, {timeout, inactivity_timer}}.


start_timer(#timers_smpp{response_time = infinity}, {response_timer, _}) ->
    undefined;
start_timer(#timers_smpp{response_time = infinity}, enquire_link_failure) ->
    undefined;
start_timer(#timers_smpp{enquire_link_time = infinity}, enquire_link_timer) ->
    undefined;
start_timer(#timers_smpp{session_init_time = infinity}, session_init_timer) ->
    undefined;
start_timer(#timers_smpp{inactivity_time = infinity}, inactivity_timer) ->
    undefined;
start_timer(#timers_smpp{response_time = Time}, {response_timer, _} = Msg) ->
    gen_fsm:start_timer(Time, Msg);
start_timer(#timers_smpp{response_time = Time}, enquire_link_failure) ->
    gen_fsm:start_timer(Time, enquire_link_failure);
start_timer(#timers_smpp{enquire_link_time = Time}, enquire_link_timer) ->
    gen_fsm:start_timer(Time, enquire_link_timer);
start_timer(#timers_smpp{session_init_time = Time}, session_init_timer) ->
    gen_fsm:start_timer(Time, session_init_timer);
start_timer(#timers_smpp{inactivity_time = Time}, inactivity_timer) ->
    gen_fsm:start_timer(Time, inactivity_timer).

%%%-----------------------------------------------------------------------------
%%% SEND PDU FUNCTIONS
%%%-----------------------------------------------------------------------------
send_pdu(Sock, Pdu, Log) ->
    case smpp_operation:pack(Pdu) of
        {ok, BinPdu} ->
            case gen_tcp:send(Sock, BinPdu) of
                ok ->
                    ok = smpp_log_mgr:pdu(Log, BinPdu);
                {error, Reason} ->
                    gen_fsm:send_all_state_event(self(), {sock_error, Reason})
            end;
        {error, _CmdId, Status, _SeqNum} ->
            gen_tcp:close(Sock),
            exit({command_status, Status})
    end.


send_enquire_link(St) ->
    SeqNum = ?INCR_SEQUENCE_NUMBER(St#st.sequence_number),
    Pdu = smpp_operation:new(?COMMAND_ID_ENQUIRE_LINK, SeqNum, []),
    ok = send_pdu(St#st.sock, Pdu, St#st.log),
    ETimer = start_timer(St#st.timers, enquire_link_timer),
    RTimer = start_timer(St#st.timers, enquire_link_failure),
    St#st{sequence_number = SeqNum,
          enquire_link_timer = ETimer,
          enquire_link_resp_timer = RTimer,
          congestion_state = 0}.


send_request(CmdId, Params, From, St) ->
    cancel_timer(St#st.inactivity_timer),
    cancel_timer(St#st.enquire_link_timer),
    SeqNum = ?INCR_SEQUENCE_NUMBER(St#st.sequence_number),
    Pdu = smpp_operation:new(CmdId, SeqNum, Params),
    ok = send_pdu(St#st.sock, Pdu, St#st.log),
    RTimer = start_timer(St#st.timers, {response_timer, SeqNum}),
    Ref = make_ref(),
    ok = smpp_req_tab:write(St#st.req_tab, {SeqNum, CmdId, RTimer, Ref}),
    gen_fsm:reply(From, Ref),
    St#st{sequence_number = SeqNum,
          enquire_link_timer = start_timer(St#st.timers, enquire_link_timer),
          inactivity_timer = start_timer(St#st.timers, inactivity_timer)}.


send_response(CmdId, Status, SeqNum, Params, Sock, Log) ->
    send_pdu(Sock, smpp_operation:new(CmdId, Status, SeqNum, Params), Log).
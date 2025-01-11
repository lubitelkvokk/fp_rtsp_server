%%%-------------------------------------------------------------------
%%% @author Alex
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(fp_storage).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(fp_storage_state, {free_ports = undefined, client_map = #{}}).
-record(client_info, {ip, audio_port, video_port, audio_server_port, video_server_port, trackID = 1, ssrc = "7B32F2BF"}).


%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
  FreePorts = [X || X <- lists:seq(15000, 16000), X rem 2 =:= 0],
  {ok, #fp_storage_state{free_ports = FreePorts, client_map = #{}}}.


handle_call({set_client_ip, ClientIP}, _From, State = #fp_storage_state{client_map = ClientMap}) ->
  ClientInfo = #client_info{ip = ClientIP},
  {Pid, _} = _From,
  UpdatedClientMap = maps:put(Pid, ClientInfo, ClientMap),
  {reply, ok, State#fp_storage_state{client_map = UpdatedClientMap}};
handle_call({reserve_port, PortType}, _From, State = #fp_storage_state{free_ports = [FreePort | Rest], client_map = ClientMap}) ->
  {Pid, _} = _From,
  ClientInfo = maps:get(Pid, ClientMap),
  case PortType of
    video_port ->
      UpdatedClientInfo = ClientInfo#client_info{video_port = FreePort};
    audio_port ->
      UpdatedClientInfo = ClientInfo#client_info{audio_port = FreePort};
    video_server_port ->
      UpdatedClientInfo = ClientInfo#client_info{video_server_port = FreePort};
    audio_server_port ->
      UpdatedClientInfo = ClientInfo#client_info{audio_server_port = FreePort}
  end,
  UpdatedClientMap = maps:put(Pid, UpdatedClientInfo, ClientMap),
  UpdatedState = State#fp_storage_state{free_ports = Rest, client_map = UpdatedClientMap},
  {reply, {ok, FreePort}, UpdatedState};
handle_call({set_client_port, PortType, NewPort}, {Pid, _}, State = #fp_storage_state{client_map = ClientMap}) ->
  ClientInfo = maps:get(Pid, ClientMap),
  case PortType of
    video_port ->
      UpdatedClientInfo = ClientInfo#client_info{video_port = NewPort};
    audio_port ->
      UpdatedClientInfo = ClientInfo#client_info{audio_port = NewPort}
  end,
  UpdatedClientMap = maps:put(Pid, UpdatedClientInfo, ClientMap),
  {reply, ok, State#fp_storage_state{client_map = UpdatedClientMap}};

handle_call({get, DataType}, _From = {Pid, _}, State = #fp_storage_state{client_map = ClientMap}) ->
  ClientInfo = case maps:get(Pid, ClientMap) of
                 undefined ->
                   exit({error, {not_registered, Pid}});
                 Info -> Info
               end,
  Data = case DataType of
           video_port -> ClientInfo#client_info.video_port;
           audio_port -> ClientInfo#client_info.audio_port;
           video_server_port -> ClientInfo#client_info.video_server_port;
           audio_server_port -> ClientInfo#client_info.audio_server_port;
           ip -> ClientInfo#client_info.ip;
           client_info -> ClientInfo
         end,
  {reply, {ok, Data}, State};

handle_call(_Request, _From, State = #fp_storage_state{}) ->
  {reply, ok, State}.

handle_cast({return_port, Port}, State = #fp_storage_state{free_ports = Ports}) ->
  {noreply, State#fp_storage_state{free_ports = [Port | Ports]}};
handle_cast(_Request, State = #fp_storage_state{}) ->
  {noreply, State}.

handle_info(_Info, State = #fp_storage_state{}) ->
  {noreply, State}.

terminate(Reason, _State) ->
  io:format("Fp storage terminating with reason: ~p~n", [Reason]),
  ok.


code_change(_OldVsn, State = #fp_storage_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

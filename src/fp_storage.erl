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

-record(fp_storage_state, {free_port_list = undefined}).

%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
  PortList = [X || X <- lists:seq(6000, 7000), X rem 2 =:= 0],
  {ok, #fp_storage_state{free_port_list = PortList}}.

handle_call({get_port}, _From, State = #fp_storage_state{free_port_list = [FreePort | Ports]}) ->
  {reply, {ok, FreePort}, State#fp_storage_state{free_port_list = Ports}};
handle_call(_Request, _From, State = #fp_storage_state{}) ->
  {reply, ok, State}.

handle_cast({put_port, Port}, State = #fp_storage_state{free_port_list = Ports}) ->
  {noreply, State#fp_storage_state{free_port_list = [Port | Ports]}};
handle_cast(_Request, State = #fp_storage_state{}) ->
  {noreply, State}.

handle_info(_Info, State = #fp_storage_state{}) ->
  {noreply, State}.

terminate(_Reason, _State = #fp_storage_state{}) ->
  ok.

code_change(_OldVsn, State = #fp_storage_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

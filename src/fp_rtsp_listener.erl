%%%-------------------------------------------------------------------
%%% @author Alex
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. янв. 2025 16:25
%%%-------------------------------------------------------------------
-module(fp_rtsp_listener).
-behaviour(gen_server).
-define(Options, [
  binary,
  {backlog, 128},
  {active, false},
  {buffer, 65536},
  {keepalive, true},
  {reuseaddr, true}
]).

-export([start_link/0, init/1, handle_info/2, terminate/2, code_change/3, handle_call/3, handle_cast/2]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
  {ok, ListenSocket} = gen_tcp:listen(7554, ?Options),
  io:format("RTSP Server started on port 7554~n"),
  accept(ListenSocket),
  {ok, ListenSocket}.

accept(ListenSocket) ->
  {ok, Socket} = gen_tcp:accept(ListenSocket),
  {ok, {ClientIP, _ClientPort}} = inet:peername(Socket),
  io:format("client ip ~p~n", [ClientIP]),

  spawn(fun() ->
    fp_rtsp_worker:start(Socket, ClientIP)
        end),
  accept(ListenSocket).

handle_info(_Msg, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.
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

-export([start_link/0, init/1, handle_info/2, handle_call/3, handle_cast/2, terminate/2, code_change/3]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
  {ok, ListenSocket} = gen_tcp:listen(8554, [binary, {active, false}, {reuseaddr, true}]),
  io:format("RTSP Server started on port 8554~n"),
  accept(ListenSocket),
  {ok, ListenSocket}.


accept(ListenSocket) ->
  spawn(fun() ->
    {ok, Socket} = gen_tcp:accept(ListenSocket),
    fp_rtsp_worker:start_link(Socket),
    accept(ListenSocket)
        end).

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

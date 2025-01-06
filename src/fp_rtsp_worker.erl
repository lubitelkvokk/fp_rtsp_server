%%%-------------------------------------------------------------------
%%% @author Alex
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. янв. 2025 16:28
%%%-------------------------------------------------------------------
-module(fp_rtsp_worker).
-behaviour(gen_server).

-export([start_link/1, init/1, handle_info/2, handle_call/3, handle_cast/2, terminate/2, code_change/3]).

start_link(Socket) ->
  gen_server:start_link(?MODULE, Socket, []).

init(Socket) ->
  io:format("New client connected~n"),
  gen_tcp:controlling_process(Socket, self()),
  {ok, Socket}.

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info({tcp, _Socket, Data}, Socket) ->
  io:format("Received: ~p~n", [Data]),
  {noreply, Socket};

handle_info({tcp_closed, _Socket}, Socket) ->
  io:format("Client disconnected~n"),
  {stop, normal, Socket};

handle_info(_Info, Socket) ->
  {noreply, Socket}.

terminate(_Reason, Socket) ->
  gen_tcp:close(Socket),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%%%-------------------------------------------------------------------
%%% @author Alex
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. янв. 2025 16:25
%%%-------------------------------------------------------------------
-module(fp_rtsp_codec).
-behaviour(gen_server).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3, encode_frame/2]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  {ok, #{}}. % Начальное состояние

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

encode_frame(StreamId, Frame) ->
  % Пример использования Frame для устранения предупреждения
  io:format("Encoding frame for stream ~p: ~p~n", [StreamId, Frame]),
  ok.



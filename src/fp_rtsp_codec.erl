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

-export([start_link/0, init/1, encode_frame/2]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  {ok, #{}}. % Начальное состояние

encode_frame(StreamId, Frame) ->
  % Логика взаимодействия с кодеком
  io:format("Encoding frame for stream ~p~n", [StreamId]),
  ok.


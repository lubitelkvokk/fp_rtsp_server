%%%-------------------------------------------------------------------
%% @doc fp_rtsp_server public API
%% @end
%%%-------------------------------------------------------------------

-module(fp_rtsp_server).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    fp_rtsp_server_sup:start_link().

stop(_State) ->
    ok.



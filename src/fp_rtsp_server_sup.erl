%%%-------------------------------------------------------------------
%% @doc fp_rtsp_server top level supervisor.
%% @end
%%%-------------------------------------------------------------------
-module(fp_rtsp_server_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  Children = [
    % Процесс RTSP-сервера
    #{id => fp_rtsp_listener,
      start => {fp_rtsp_listener, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker}
  ],
  {ok, {{one_for_one, 10, 10}, Children}}.


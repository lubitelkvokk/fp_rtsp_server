%%%-------------------------------------------------------------------
%%% @author Alex
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 10. янв. 2025 1:02
%%%-------------------------------------------------------------------
-author("Alex").
-record(client_info, {ip, audio_port, video_port, audio_server_port, video_server_port, trackID = 1, ssrc = 16#7B32F2BF}).

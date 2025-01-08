%%%-------------------------------------------------------------------
%%% @author Alex
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. янв. 2025 17:20
%%%-------------------------------------------------------------------
-module(fp_rtp_worker).
-author("Alex").

%% API
-export([send_video/4, find_and_send_video/2]).
-record(client_info, {ip, audio_port, video_port, audio_server_port, video_server_port, trackID = 1, ssrc = 16#7B32F2BF}).
% Генерация RTP-заголовка
generate_rtp_header(SequenceNumber, Timestamp, SSRCString, Marker, PayloadType) ->
  SSRC = list_to_integer(SSRCString, 16),
  <<2:2, 0:1, 0:1, 0:4, Marker:1, PayloadType:7, SequenceNumber:16, Timestamp:32, SSRC:32>>.


% Разделение видео на RTP-пакеты
split_video_into_rtp(Data, MTU, SequenceNumber, Timestamp, TimestampIncrement, SSRC, PayloadType) ->
  HeaderSize = 12, % Размер RTP-заголовка
  MaxPayloadSize = MTU - HeaderSize,
  split_video_into_rtp(Data, MaxPayloadSize, SequenceNumber, Timestamp, TimestampIncrement, SSRC, PayloadType, []).

split_video_into_rtp(<<>>, _MaxPayloadSize, _Seq, _Timestamp, _TimestampIncrement, _SSRC, _PT, Packets) ->
  lists:reverse(Packets);

split_video_into_rtp(Data, MaxPayloadSize, SequenceNumber, Timestamp, TimestampIncrement, SSRC, PayloadType, Packets) ->
  case Data of
    <<Chunk:MaxPayloadSize/binary, Rest/binary>> ->
      Marker = if Rest == <<>> -> 1; true -> 0 end, % Устанавливаем Marker для последнего пакета
      Header = generate_rtp_header(SequenceNumber, Timestamp, SSRC, Marker, PayloadType),
      Packet = <<Header/binary, Chunk/binary>>,
      split_video_into_rtp(Rest, MaxPayloadSize, SequenceNumber + 1, Timestamp + TimestampIncrement, TimestampIncrement, SSRC, PayloadType, [Packet | Packets]);
    _ ->
      Marker = 1,
      Header = generate_rtp_header(SequenceNumber, Timestamp, SSRC, Marker, PayloadType),
      Packet = <<Header/binary, Data/binary>>,
      lists:reverse([Packet | Packets])
  end.

% Отправка RTP-пакетов с задержкой
send_video(Socket, IPv4, Port, RTPPackets) ->
  lists:foreach(
    fun(Packet) ->
%%      io:format("Packet data ~p~n", [Packet]),
      % Отправка пакета
      gen_udp:send(Socket, IPv4, Port, Packet),
      % Задержка (например, 40 мс для ~25 fps)
      timer:sleep(40)
    end,
    RTPPackets).


find_and_send_video(FileName, ClientInfo = #client_info{ssrc = SSRC, video_server_port = ServerPort, ip = ClientIp, video_port = ClientPort}) ->
  io:format("Starting video stream: ~s~n", [FileName]),
  io:format("Client info: ~p~n", [ClientInfo]),

  % Читаем заранее подготовленный файл
  case file:read_file(FileName) of
    {ok, Data} ->
      io:format("File ~s successfully loaded~n", [FileName]),
      MTU = 1400,
      SequenceNumber = 0,
      Timestamp = 0,
      PayloadType = 96,
      Packets = split_video_into_rtp(Data, MTU, SequenceNumber, Timestamp, 3600, SSRC, PayloadType),

      % Открытие UDP-сокета
      {ok, Socket} = gen_udp:open(ServerPort, [binary, {active, true}]),
%%      {ok, Socket} = gen_udp:open(15000),
      io:format("Streaming on port ~p to ~p~n", [ServerPort, ClientPort]),

      % Отправка пакетов
      send_video(Socket, ClientIp, ClientPort, Packets),
      gen_udp:close(Socket),
      io:format("Video streaming complete~n"),
      ok;

    {error, Reason} ->
      io:format("Failed to open file ~s: ~p~n", [FileName, Reason]),
      {error, Reason}
  end.


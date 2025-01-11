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
-include("client_info.hrl").

generate_rtp_header(SequenceNumber, Timestamp, SSRCString, Marker, PayloadType) ->
  SSRC = case SSRCString of
           <<_Binary/binary>> -> list_to_integer(binary_to_list(SSRCString), 16);
           _List -> list_to_integer(SSRCString, 16)
         end,
  <<2:2, 0:1, 0:1, 0:4, Marker:1, PayloadType:7, SequenceNumber:16, Timestamp:32, SSRC:32>>.

%% Разделение H.264 на NAL-юниты
split_nal_units(Data) ->
  lists:filter(fun(Unit) -> byte_size(Unit) > 0 end, binary:split(Data, <<0, 0, 0, 1>>, [global, trim])).


create_rtp_packets(<<>>, _MTU, _SequenceNumber, _Timestamp, _SSRC, _PayloadType) ->
  [];
create_rtp_packets(NAL, MTU, SequenceNumber, Timestamp, SSRC, PayloadType) ->
  HeaderSize = 12,
  MaxPayloadSize = MTU - HeaderSize,
  %% Преобразование NAL-заголовка
  NALHeader = binary:part(NAL, 0, 1),
  NALHeaderInt = binary:at(NALHeader, 0), %% Преобразуем <<6>> в 6
  NALPayload = binary:part(NAL, 1, byte_size(NAL) - 1),
  NalType = NALHeaderInt band 16#1F, %% Последние 5 бит NAL-заголовка

  case byte_size(NAL) =< MaxPayloadSize of
    true ->
      %% Маленький NAL-юнит
      Marker = 1,
      Header = generate_rtp_header(SequenceNumber, Timestamp, SSRC, Marker, PayloadType),
      [<<Header/binary, NAL/binary>>];

    false ->
      %% Большой NAL-юнит (FU-A)
      NALHeaderInt = binary:at(NALHeader, 0), %% Преобразуем <<...>> в целое число
      FUIndicator = (NALHeaderInt band 16#E0) bor 28,
      FirstPacketHeader = 128 bor NalType, %% FU Header (Start=1)
      FirstPacket = <<FUIndicator, FirstPacketHeader, (binary:part(NALPayload, 0, MaxPayloadSize))/binary>>,

      RemainingPayload = binary:part(NALPayload, MaxPayloadSize, byte_size(NALPayload) - MaxPayloadSize),
      rtp_packets_fua(RemainingPayload, MaxPayloadSize, SequenceNumber + 1, Timestamp, SSRC, PayloadType, FUIndicator, NalType, [FirstPacket])
  end.


rtp_packets_fua(<<>>, _MaxPayloadSize, _SequenceNumber, _Timestamp, _SSRC, _PayloadType, _FUIndicator, _NalType, Packets) ->
  lists:reverse(Packets);

rtp_packets_fua(Data, MaxPayloadSize, SequenceNumber, Timestamp, SSRC, PayloadType, FUIndicator, NalType, Packets) ->
  case byte_size(Data) =< MaxPayloadSize of
    true ->
      %% Последний фрагмент
      Marker = 1,
      FUHeader = 64 bor NalType, %% Start=0, End=1
      Header = generate_rtp_header(SequenceNumber, Timestamp, SSRC, Marker, PayloadType),
      Packet = <<Header/binary, FUIndicator, FUHeader, Data/binary>>,
      lists:reverse([Packet | Packets]);

    false ->
      %% Обычный фрагмент
      Chunk = binary:part(Data, 0, MaxPayloadSize),
      Rest = binary:part(Data, MaxPayloadSize, byte_size(Data) - MaxPayloadSize),
      Marker = 0,
      FUHeader = NalType, %% Start=0, End=0
      Header = generate_rtp_header(SequenceNumber, Timestamp, SSRC, Marker, PayloadType),
      Packet = <<Header/binary, FUIndicator, FUHeader, Chunk/binary>>,
      rtp_packets_fua(Rest, MaxPayloadSize, SequenceNumber + 1, Timestamp, SSRC, PayloadType, FUIndicator, NalType, [Packet | Packets])
  end.

%% Генерация RTP-пакетов для всего H.264
generate_rtp_packets(Data, MTU, SequenceNumber, Timestamp, TimestampIncrement, SSRC, PayloadType) ->
  NALUnits = split_nal_units(Data),
  lists:foldl(
    fun(NAL, {Packets, SeqNum, TS}) ->
      NALPackets = create_rtp_packets(NAL, MTU, SeqNum, TS, SSRC, PayloadType),
      {Packets ++ NALPackets, SeqNum + length(NALPackets), TS + TimestampIncrement}
    end,
    {[], SequenceNumber, Timestamp},
    NALUnits
  ).

%% Отправка RTP-пакетов
send_video(Socket, IPv4, Port, RTPPackets) ->
  lists:foreach(
    fun(Packet) ->
      gen_udp:send(Socket, IPv4, Port, Packet),
      timer:sleep(2)
    end,
    RTPPackets
  ).

%% Найти и отправить видео
find_and_send_video(FileName, ClientInfo = #client_info{ssrc = SSRC, video_server_port = ServerPort, ip = ClientIp, video_port = ClientPort}) ->
  io:format("Starting video stream: ~s~n", [FileName]),
  io:format("Client info: ~p~n", [ClientInfo]),

  case file:read_file(FileName) of
    {ok, Data} ->
      case byte_size(Data) of
        0 ->
          io:format("Error: File is empty or invalid~n"),
          {error, empty_file};
        _ ->
          MTU = 1400,
          SequenceNumber = 0,
          Timestamp = 0,
          TimestampIncrement = 2500,
          PayloadType = 96,

          {Packets, _, _} = generate_rtp_packets(Data, MTU, SequenceNumber, Timestamp, TimestampIncrement, SSRC, PayloadType),

          %% Открываем сокет
          {ok, Socket} = gen_udp:open(ServerPort, [binary, {active, false}]),
          io:format("Streaming on port ~p to ~p~n", [ServerPort, ClientPort]),

          %% Отправляем RTP-пакеты
          send_video(Socket, ClientIp, ClientPort, Packets),
          gen_udp:close(Socket),
          io:format("Video streaming complete~n"),
          ok
      end;


    {error, Reason} ->
      io:format("Failed to open file ~s: ~p~n", [FileName, Reason]),
      {error, Reason}
  end.

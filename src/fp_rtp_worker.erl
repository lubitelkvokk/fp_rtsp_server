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
-export([split_video_into_rtp/6, send_video/4]).

generate_rtp_header(SequenceNumber, Timestamp, SSRC, Marker, PayloadType) ->
  << 2:2,    % Version (2)
    0:1,    % Padding
    0:1,    % Extension
    0:4,    % CSRC count
    Marker:1,
    PayloadType:7,
    SequenceNumber:16,
    Timestamp:32,
    SSRC:32 >>.

split_video_into_rtp(Data, MTU, SequenceNumber, Timestamp, SSRC, PayloadType) ->
  HeaderSize = 12, % Размер RTP-заголовка
  MaxPayloadSize = MTU - HeaderSize,
  split_video_into_rtp(Data, MaxPayloadSize, SequenceNumber, Timestamp, SSRC, PayloadType, []).

split_video_into_rtp(<<>>, _MaxPayloadSize, _Seq, _Timestamp, _SSRC, _PT, Packets) ->
  lists:reverse(Packets);

split_video_into_rtp(Data, MaxPayloadSize, SequenceNumber, Timestamp, SSRC, PayloadType, Packets) ->
  % Отделяем полезную нагрузку для текущего пакета
  case Data of
    <<Chunk:MaxPayloadSize/binary, Rest/binary>> ->
      Marker = if Rest == <<>> -> 1; true -> 0 end, % Устанавливаем Marker для последнего пакета
      Header = generate_rtp_header(SequenceNumber, Timestamp, SSRC, Marker, PayloadType),
      Packet = <<Header/binary, Chunk/binary>>,
      split_video_into_rtp(Rest, MaxPayloadSize, SequenceNumber + 1, Timestamp, SSRC, PayloadType, [Packet | Packets]);
    _ ->
      % Последний оставшийся фрагмент
      Marker = 1,
      Header = generate_rtp_header(SequenceNumber, Timestamp, SSRC, Marker, PayloadType),
      Packet = <<Header/binary, Data/binary>>,
      lists:reverse([Packet | Packets])
  end.

% @param Socket - UDP сокет сервера, открытый на определенном порту
% @param IPv4 - целевой адрес
% @param Port - целевой порт
% @param RTPPackets - передаваемые данные
send_video(Socket, IPv4, Port, RTPPackets) ->
  % Создаем UDP-сокет
  {ok, Socket} = gen_udp:open(Port, [{active, false}]),

  % Отправляем пакеты
  lists:foreach(fun(Packet) -> gen_udp:send(Socket, IPv4, Port, Packet) end, RTPPackets).

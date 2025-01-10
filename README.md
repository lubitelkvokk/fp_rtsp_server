lab2
=====
- Студент: ``` Михайлов Павел ```
- ИСУ: ``` 367403 ```
- Вариант: ``` RTSP Server ```

## Суть проекта
Реализовать RTSP Streaming server на Erlang, используя OTP framework. В реализацию должен быть использован supervisor, gen_server, возможность обработки нескольких клиентов.

Пример последовательности запросов RTSP(Real Time Streaming Protocol) протока
```text
01: OPTIONS rtsp://192.168.0.254/jpeg RTSP/1.0
02: CSeq: 1
03: User-Agent: VLC media player (LIVE555 Streaming Media v2008.07.24)
04: 
05: RTSP/1.0 200 OK
06: CSeq: 1
07: Date: Fri, Apr 23 2010 19:54:20 GMT
08: Public: OPTIONS, DESCRIBE, SETUP, TEARDOWN, PLAY, PAUSE
09: 
10: DESCRIBE rtsp://192.168.0.254/jpeg RTSP/1.0
11: CSeq: 2
12: Accept: application/sdp
13: User-Agent: VLC media player (LIVE555 Streaming Media v2008.07.24)
14: 
15: RTSP/1.0 200 OK
16: CSeq: 2
17: Date: Fri, Apr 23 2010 19:54:20 GMT
18: Content-Base: rtsp://192.168.0.254/jpeg/
19: Content-Type: application/sdp
20: Content-Length: 442
21: x-Accept-Dynamic-Rate: 1
22: 
23: v=0
24: o=- 1272052389382023 1 IN IP4 0.0.0.0
25: s=Session streamed by "nessyMediaServer"
26: i=jpeg
27: t=0 0
28: a=tool:LIVE555 Streaming Media v2008.04.09
29: a=type:broadcast
30: a=control:*
31: a=range:npt=0-
32: a=x-qt-text-nam:Session streamed by "nessyMediaServer"
33: a=x-qt-text-inf:jpeg
34: m=video 0 RTP/AVP 26
35: c=IN IP4 0.0.0.0
36: a=control:track1
37: a=cliprect:0,0,720,1280
38: a=framerate:25.000000
39: m=audio 7878 RTP/AVP 0
40: a=rtpmap:0 PCMU/8000/1
41: a=control:track2
42: 
43: 
44: SETUP rtsp://192.168.0.254/jpeg/track1 RTSP/1.0
45: CSeq: 3
46: Transport: RTP/AVP;unicast;client_port=41760-41761
47: User-Agent: VLC media player (LIVE555 Streaming Media v2008.07.24)
48: 
49: RTSP/1.0 200 OK
50: CSeq: 3
51: Cache-Control: must-revalidate
52: Date: Fri, Apr 23 2010 19:54:20 GMT
53: Transport: RTP/AVP;unicast;destination=192.168.0.4;source=192.168.0.254;client_port=41760-41761;
            server_port=6970-6971
54: Session: 1
55: x-Transport-Options: late-tolerance=1.400000
56: x-Dynamic-Rate: 1
57: 
58: SETUP rtsp://192.168.0.254/jpeg/track2 RTSP/1.0
59: CSeq: 4
60: Transport: RTP/AVP;unicast;client_port=7878-7879
61: Session: 1
62: User-Agent: VLC media player (LIVE555 Streaming Media v2008.07.24)
63: 
64: RTSP/1.0 200 OK
65: CSeq: 4
66: Cache-Control: must-revalidate
67: Date: Fri, Apr 23 2010 19:54:20 GMT
68: Transport: RTP/AVP;unicast;destination=192.168.0.4;source=192.168.0.254;client_port=7878-7879;
            server_port=6972-6973
69: Session: 1
70: x-Transport-Options: late-tolerance=1.400000
71: x-Dynamic-Rate: 1
72: 
73: PLAY rtsp://192.168.0.254/jpeg/ RTSP/1.0
74: CSeq: 5
75: Session: 1
76: Range: npt=0.000-
77: User-Agent: VLC media player (LIVE555 Streaming Media v2008.07.24)
78: 
79: RTSP/1.0 200 OK
80: CSeq: 5
81: Date: Fri, Apr 23 2010 19:54:20 GMT
82: Range: npt=0.000-
83: Session: 1
84: RTP-Info: url=rtsp://192.168.0.254/jpeg/track1;seq=20730;
            rtptime=3869319494,url=rtsp://192.168.0.254/jpeg/track2;seq=33509;rtptime=3066362516
85: 
86: # В этот момент начинается передача контента и следующая команда вызывается для остановки вещания
87: 
88: TEARDOWN rtsp://192.168.0.254/jpeg/ RTSP/1.0
89: CSeq: 6
90: Session: 1
91: User-Agent: VLC media player (LIVE555 Streaming Media v2008.07.24)
92: 
93: RTSP/1.0 200 OK
94: CSeq: 6
95: Date: Fri, Apr 23 2010 19:54:25 GMT
```

## Supervisor
```erl
-module(fp_rtsp_server_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  Children = [
    % Глобальное хранилище
    #{id => fp_storage,
      start => {fp_storage, start_link, []},
      restart => permanent,
      shutdown => 100000,
      type => worker,
      modules => [fp_worker]
    },
    % Процесс RTSP-сервера
    #{id => fp_rtsp_listener,
      start => {fp_rtsp_listener, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker,
      modules => [fp_rtsp_listener]
    }

  ],

  {ok, {{one_for_one, 100, 60}, Children}}.
```

## Gen_servers
Модуль приема подключений и вызов обработчика для них 
```erl
-module(fp_rtsp_listener).
-behaviour(gen_server).
-define(Options, [
  binary,
  {backlog, 128},
  {active, false},
  {buffer, 65536},
  {keepalive, true},
  {reuseaddr, true}
]).

-export([start_link/0, init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
  process_flag(trap_exit, true),
  {ok, ListenSocket} = gen_tcp:listen(7554, ?Options),
  io:format("RTSP Server started on port 7554~n"),
  accept(ListenSocket),
  {ok, ListenSocket}.

accept(ListenSocket) ->
  {ok, Socket} = gen_tcp:accept(ListenSocket),
  {ok, {ClientIP, _ClientPort}} = inet:peername(Socket),
  io:format("client ip ~p~n", [ClientIP]),

  spawn_link(fun() ->
    fp_rtsp_worker:start(Socket, ClientIP)
        end),
  accept(ListenSocket).

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.
```

Модуль обработки подключений
```erl
-module(fp_rtsp_worker).

-export([loop/2, start/2]).
-record(rtsp_message, {
  method,          % Метод запроса: START, DESCRIBE, SETUP и т.д.
  uri,             % URI, на который направлен запрос
  version,         % Версия протокола, например, RTSP/1.0
  headers = #{},   % Заголовки в формате Map
  body = <<>>,      % Тело сообщения (может быть пустым)
  session_id = undefined,
  client_ports = undefined
}).
start(Socket, ClientIp) ->
  SessionId = rand:uniform(1000000) + 1000000,
  io:format("Session id ~p~n", [SessionId]),
  gen_server:call(fp_storage, {set_client_ip, ClientIp}),
  loop(Socket, SessionId).

loop(Socket, SessionId) ->
  case gen_tcp:recv(Socket, 0) of
    {ok, Data} ->
      io:format("Received raw data: ~p~n", [Data]),
      case parse(Data) of
        error ->
          gen_tcp:send(Socket, <<"RTSP/1.0 400 Bad Request\r\n\r\n">>),
          loop(Socket, SessionId);
        Message ->
          UpdatedMessage = Message#rtsp_message{session_id = SessionId},
          Response = service(UpdatedMessage),
          gen_tcp:send(Socket, Response),
          loop(Socket, SessionId)
      end;
    {error, closed} ->
      io:format("Client disconnected~n"),
      ok
  end.

get_storage_data(DataType) ->
  case gen_server:call(fp_storage, {get, DataType}) of
    {ok, Reply} -> Reply;
    _ -> undefined
  end.

parse(Data) when is_binary(Data) ->
  % Очистка данных
  CleanedData = binary:replace(Data, <<"\r\n">>, <<"\n">>, [global]),
  Lines = binary:split(CleanedData, <<"\n">>, [global]),

  case Lines of
    [RequestLine | Rest] ->
      TrimmedRequestLine = trim_binary(RequestLine),
      CleanedRequestLine = clean_request_line(TrimmedRequestLine),

      case split_request_line(CleanedRequestLine) of
        {ok, Method, URI, Version} ->
          {HeadersBin, Body} = lists:foldl(fun parse_line/2, {[], <<>>}, Rest),
          Headers = parse_headers(HeadersBin),

          % Извлечение client_port
          Transport = maps:get(<<"Transport">>, Headers, <<>>),
          ClientPorts = extract_client_port(Transport),
          #rtsp_message{
            method = binary_to_atom(Method, utf8),
            uri = URI,
            version = Version,
            headers = Headers,
            body = Body,
            client_ports = ClientPorts
          };
        {error, _Line} ->
          error
      end;
    _ ->
      error
  end;
parse(_) ->
  error.


extract_client_port(Transport) ->
  case binary:match(Transport, <<"client_port=">>) of
    {Pos, _Length} ->
      % Извлекаем подстроку после "client_port="
      PortString = binary:part(Transport, Pos + 12, byte_size(Transport) - (Pos + 12)),
      % Разделяем порты по символу "-"
      case binary:split(PortString, <<"-">>, [global]) of
        [StartPort, EndPort] ->
          {binary_to_integer(StartPort), binary_to_integer(EndPort)};
        _ ->
          undefined
      end;
    nomatch ->
      undefined
  end.

trim_binary(Bin) when is_binary(Bin) ->
  re:replace(Bin, <<"^[ \t]+|[ \t]+$">>, <<>>, [global, {return, binary}]).

clean_request_line(Line) ->
  re:replace(Line, <<" +">>, <<" ">>, [global, {return, binary}]).

split_request_line(RequestLine) ->
  case binary:split(RequestLine, <<" ">>, [global]) of
    [Method, URI, Version] ->
      {ok, Method, URI, Version};
    _ ->
      {error, RequestLine}
  end.

parse_line(<<>>, {Headers, Body}) ->
  {lists:reverse(Headers), Body};
parse_line(Line, {Headers, _Body}) ->
  {[Line | Headers], <<>>}.

parse_headers(Lines) ->
  lists:foldl(fun(Line, Acc) ->
    case binary:split(Line, <<": ">>) of
      [Key, Value] -> maps:put(Key, Value, Acc);
      _ -> Acc
    end
              end, #{}, Lines).

parse_uri(URI) when is_binary(URI) ->

  % Разделяем строку и извлекаем последний сегмент
  case binary:split(URI, <<"/">>, [global]) of
    [] -> <<>>;               % Если строка пустая, возвращаем пустую строку
    Segments -> lists:last(Segments)
  end.

service(#rtsp_message{method = 'OPTIONS', headers = Headers} = _Message) ->
  CSeq = maps:get(<<"CSeq">>, Headers, undefined),
  % Ответ с перечнем доступных методов
  SupportedMethods = <<"DESCRIBE, SETUP, TEARDOWN, PLAY, PAUSE">>,
  io:format("Handling OPTIONS request~n"),
  <<"RTSP/1.0 200 OK\r\n",
    "CSeq: ", CSeq/binary, "\r\n",
    "Public: ", SupportedMethods/binary, "\r\n\r\n">>;

service(#rtsp_message{method = 'DESCRIBE', uri = URI, headers = Headers, session_id = SessionId} = _Message) ->
  % Извлечение CSeq
  CSeq = maps:get(<<"CSeq">>, Headers, undefined),
  io:format("Handling DESCRIBE request for ~s with CSeq ~p~n", [URI, CSeq]),

  % Парсим URI (например, для проверки ресурса)
  ResourceName = parse_uri(URI),
  io:format("resource name = ~p~n", [ResourceName]),
  io:format("session id = ~p~n", [SessionId]),
  SessionIdBinary = integer_to_binary(SessionId),

  % Создаем тело сообщения (SDP)
  SDP = <<"v=0\r\n",
    "o=lubitelkvokk ", SessionIdBinary/binary, " ", SessionIdBinary/binary, " IN IP4 127.0.0.1\r\n",
    "s=SDP Seminar\r\n",
    "i=RTSP Erlang server\r\n",
    "u=http://www.additional.info.com\r\n",
    "e=pasha110.mikhailov@yandex.ru\r\n",
    "c=IN IP4 127.0.0.1\r\n",
    "t=0 30\r\n",
    "a=recvonly\r\n",
    "m=video 0 RTP/AVP 96\r\n",
    "b=AS:50000\r\n",
    "a=framerate:30.0\r\n",
    "a=rtpmap:96 H264/90000\r\n",
    "a=fmtp:96 packetization-mode=1;profile-level-id=64003E;sprop-parameter-sets=ZAA+rNlB4L/lwFqDAIMgAAADACAD0JAB4QCDLA==,74bywA==\r\n",
    "\r\n">>,


  % Рассчитываем длину тела сообщения
  ContentLength = integer_to_binary(byte_size(SDP)),
  % Формируем полный ответ
  Response = <<"RTSP/1.0 200 OK\r\n",
    "CSeq: ", CSeq/binary, "\r\n",
    "Content-Type: application/sdp\r\n",
    "Content-Base: rtsp://127.0.0.1:7554/abob\r\n",
    "Content-Length: ", ContentLength/binary, "\r\n",
    "\r\n",
    SDP/binary>>,

  Response;
service(#rtsp_message{method = 'SETUP', uri = URI, session_id = SessionId, headers = Headers, client_ports = {UdpPort, RTCPPort}} = _Message) ->
  SessionIdBinary = integer_to_binary(SessionId),
  CSeq = maps:get(<<"CSeq">>, Headers, undefined),
  {ok, ServerPort} = gen_server:call(fp_storage, {reserve_port, video_server_port}),
  % TODO Does RTCPPort need to be implemented?
  gen_server:call(fp_storage, {set_client_port, video_port, UdpPort}), % branching of two case (audio and video port). While not realised

  ServerRTCPPort = ServerPort + 1,
  io:format("free port ~p~n", [ServerPort]),
  io:format("Handling SETUP request for ~s~n", [URI]),
  <<"RTSP/1.0 200 OK\r\n",
    "CSeq: ", CSeq/binary, "\r\n",
    "Cache-control: no-cache\r\n",
    "Session: ", SessionIdBinary/binary, "\r\n", % TODO set timeout
    "Transport: RTP/AVP;unicast;",
    "client_port=",
    (integer_to_binary(UdpPort))/binary, "-", (integer_to_binary(RTCPPort))/binary,
    ";source=127.0.0.1;",
    "server_port=",
    (integer_to_binary(ServerPort))/binary, "-", (integer_to_binary(ServerRTCPPort))/binary, ";",
    "ssrc=7B32F2BF\r\n",
    "\r\n">>;

service(#rtsp_message{method = 'PLAY', uri = URI,
  headers = Headers, session_id = SessionId} = _Message) ->
  CSeq = maps:get(<<"CSeq">>, Headers, undefined),
  io:format("Handling PLAY request for ~s~n", [URI]),

  %starting send rtp packets
  spawn(fp_rtp_worker, find_and_send_video, ["priv/resources/output_fixed.h264", get_storage_data(client_info)]),
  <<"RTSP/1.0 200 OK\r\n",
    "CSeq: ", CSeq/binary, "\r\n",
    "RTP-Info: url=", URI/binary, "/trackID=1;seq=1;rtptime=0\r\n",
    "Range: npt=0.0-30.0\r\n",
    "Session: ", (integer_to_binary(SessionId))/binary, ";timeout=60\r\n",
    "Server: Erlang RTSP Server\r\n",
    "\r\n">>;

service(#rtsp_message{method = 'TEARDOWN'} = _Message) ->
  io:format("special usupported for supervisor work checking~n"),
  exit(not_implemented);

service(#rtsp_message{method = Method}) ->
  io:format("Unknown method: ~s~n", [Method]),
  <<"RTSP/1.0 501 Not Implemented\r\n\r\n">>.
```

Модель хранения параметров, отправленных плеером/клиентом
``` erl
-module(fp_storage).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(fp_storage_state, {free_ports = undefined, client_map = #{}}).
-record(client_info, {ip, audio_port, video_port, audio_server_port, video_server_port, trackID = 1, ssrc = "7B32F2BF"}).


%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
  FreePorts = [X || X <- lists:seq(15000, 16000), X rem 2 =:= 0],
  {ok, #fp_storage_state{free_ports = FreePorts, client_map = #{}}}.


handle_call({set_client_ip, ClientIP}, _From, State = #fp_storage_state{client_map = ClientMap}) ->
  ClientInfo = #client_info{ip = ClientIP},
  {Pid, _} = _From,
  UpdatedClientMap = maps:put(Pid, ClientInfo, ClientMap),
  {reply, ok, State#fp_storage_state{client_map = UpdatedClientMap}};
handle_call({reserve_port, PortType}, _From, State = #fp_storage_state{free_ports = [FreePort | Rest], client_map = ClientMap}) ->
  {Pid, _} = _From,
  ClientInfo = maps:get(Pid, ClientMap),
  case PortType of
    video_port ->
      UpdatedClientInfo = ClientInfo#client_info{video_port = FreePort};
    audio_port ->
      UpdatedClientInfo = ClientInfo#client_info{audio_port = FreePort};
    video_server_port ->
      UpdatedClientInfo = ClientInfo#client_info{video_server_port = FreePort};
    audio_server_port ->
      UpdatedClientInfo = ClientInfo#client_info{audio_server_port = FreePort}
  end,
  UpdatedClientMap = maps:put(Pid, UpdatedClientInfo, ClientMap),
  UpdatedState = State#fp_storage_state{free_ports = Rest, client_map = UpdatedClientMap},
  {reply, {ok, FreePort}, UpdatedState};
handle_call({set_client_port, PortType, NewPort}, {Pid, _}, State = #fp_storage_state{client_map = ClientMap}) ->
  ClientInfo = maps:get(Pid, ClientMap),
  case PortType of
    video_port ->
      UpdatedClientInfo = ClientInfo#client_info{video_port = NewPort};
    audio_port ->
      UpdatedClientInfo = ClientInfo#client_info{audio_port = NewPort}
  end,
  UpdatedClientMap = maps:put(Pid, UpdatedClientInfo, ClientMap),
  {reply, ok, State#fp_storage_state{client_map = UpdatedClientMap}};

handle_call({get, DataType}, _From = {Pid, _}, State = #fp_storage_state{client_map = ClientMap}) ->
  ClientInfo = case maps:get(Pid, ClientMap) of
                 undefined ->
                   % Генерируем ошибку, чтобы супервизор мог перезапустить процесс
                   exit({error, {not_registered, Pid}});
                 Info -> Info
               end,
  Data = case DataType of
           video_port -> ClientInfo#client_info.video_port;
           audio_port -> ClientInfo#client_info.audio_port;
           video_server_port -> ClientInfo#client_info.video_server_port;
           audio_server_port -> ClientInfo#client_info.audio_server_port;
           ip -> ClientInfo#client_info.ip;
           client_info -> ClientInfo
         end,
  {reply, {ok, Data}, State};

handle_call(_Request, _From, State = #fp_storage_state{}) ->
  {reply, ok, State}.

handle_cast({return_port, Port}, State = #fp_storage_state{free_ports = Ports}) ->
  {noreply, State#fp_storage_state{free_ports = [Port | Ports]}};
handle_cast(_Request, State = #fp_storage_state{}) ->
  {noreply, State}.

handle_info(_Info, State = #fp_storage_state{}) ->
  {noreply, State}.

terminate(Reason, _State) ->
  io:format("Fp storage terminating with reason: ~p~n", [Reason]),
  ok.


code_change(_OldVsn, State = #fp_storage_state{}, _Extra) ->
  {ok, State}.
```

Модель разбиения видео на rtp пакеты и отправки их клиенту
```erl
-module(fp_rtp_worker).
-author("Alex").

%% API
-export([send_video/4, find_and_send_video/2]).
-include("client_info.hrl").

generate_rtp_header(SequenceNumber, Timestamp, SSRCString, Marker, PayloadType) ->
  %% Преобразуем SSRC в целое число, если это строка
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
      timer:sleep(5)
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
          TimestampIncrement = 900,
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
```

## Результат работы
```text
  RTSP Server started on port 7554
client ip {127,0,0,1}
Session id 1499454
Received raw data: <<"OPTIONS rtsp://localhost:7554/abob RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: LibVLC/3.0.20 (LIVE555 Streaming Media v2016.11.28)\r\n\r\n">>
Handling OPTIONS request
Received raw data: <<"DESCRIBE rtsp://localhost:7554/abob RTSP/1.0\r\nCSeq: 3\r\nUser-Agent: LibVLC/3.0.20 (LIVE555 Streaming Media v2016.11.28)\r\nAccept: application/sdp\r\n\r\n">>
Handling DESCRIBE request for rtsp://localhost:7554/abob with CSeq <<"3">>
resource name = <<"abob">>
session id = 1499454
Received raw data: <<"SETUP rtsp://127.0.0.1:7554/abob/ RTSP/1.0\r\nCSeq: 4\r\nUser-Agent: LibVLC/3.0.20 (LIVE555 Streaming Media v2016.11.28)\r\nTransport: RTP/AVP;unicast;client_port=50872-50873\r\n\r\n">>
free port 15000
Handling SETUP request for rtsp://127.0.0.1:7554/abob/
Received raw data: <<"PLAY rtsp://127.0.0.1:7554/abob RTSP/1.0\r\nCSeq: 5\r\nUser-Agent: LibVLC/3.0.20 (LIVE555 Streaming Media v2016.11.28)\r\nSession: 1499454\r\nRange: npt=0.000-\r\n\r\n">>
Handling PLAY request for rtsp://127.0.0.1:7554/abob
Starting video stream: priv/resources/output_fixed.h264
Client info: {client_info,{127,0,0,1},
                          undefined,50872,undefined,15000,1,"7B32F2BF"}
Streaming on port 15000 to 50872
Received raw data: <<"TEARDOWN rtsp://127.0.0.1:7554/abob RTSP/1.0\r\nCSeq: 6\r\nUser-Agent: LibVLC/3.0.20 (LIVE555 Streaming Media v2016.11.28)\r\nSession: 1499454\r\n\r\n">>
special usupported for supervisor work checking
  ```


  

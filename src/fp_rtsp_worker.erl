%%%-------------------------------------------------------------------
%%% @author Alex
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. янв. 2025 16:28
%%%-------------------------------------------------------------------
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
    "t=0 0\r\n",
    "a=recvonly\r\n",
    "m=video 0 RTP/AVP 97\r\n",
    "b=AS:50000\r\n",
    "a=framerate:30.0\r\n",
%%    "a=control:rtsp://172.20.49.113:7554/abob/trackID=1",
    "a=rtpmap:96 H264/90000\r\n",
    "a=fmtp:96 packetization-mode=1;profile-level-id=42C01E;sprop-parameter-sets=Z0IAKeKQFAe2AtwEBAaQeJEV,aM48gA==\r\n",
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
    "Range: npt=0.0-166.0\r\n",
    "Session: ", (integer_to_binary(SessionId))/binary, ";timeout=60\r\n",
    "Server: Erlang RTSP Server\r\n",
    "\r\n">>;

service(#rtsp_message{method = Method}) ->
  io:format("Unknown method: ~s~n", [Method]),
  <<"RTSP/1.0 501 Not Implemented\r\n\r\n">>.

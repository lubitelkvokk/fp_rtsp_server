%%%-------------------------------------------------------------------
%%% @author Alex
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. янв. 2025 16:28
%%%-------------------------------------------------------------------
-module(fp_rtsp_worker).

-export([loop/2]).
-record(rtsp_message, {
  method,          % Метод запроса: START, DESCRIBE, SETUP и т.д.
  uri,             % URI, на который направлен запрос
  version,         % Версия протокола, например, RTSP/1.0
  headers = #{},   % Заголовки в формате Map
  body = <<>>,      % Тело сообщения (может быть пустым)
  session_id = undefined
}).

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

parse(Data) when is_binary(Data) ->
  % Удаляем лишние символы и заменяем \r\n на \n
  CleanedData = binary:replace(Data, <<"\r\n">>, <<"\n">>, [global]),

  % Разделяем данные на строки
  Lines = binary:split(CleanedData, <<"\n">>, [global]),

  case Lines of
    [RequestLine | Rest] ->
      % Удаляем лишние пробелы в строке запроса
      TrimmedRequestLine = trim_binary(RequestLine),
      CleanedRequestLine = clean_request_line(TrimmedRequestLine),

      % Разбираем первую строку
      case split_request_line(CleanedRequestLine) of
        {ok, Method, URI, Version} ->
          % Разбираем заголовки и тело
          {HeadersBin, Body} = lists:foldl(fun parse_line/2, {[], <<>>}, Rest),
          Headers = parse_headers(HeadersBin),
          #rtsp_message{
            method = binary_to_atom(Method, utf8),
            uri = URI,
            version = Version,
            headers = Headers,
            body = Body
          };
        {error, _Line} ->
          error
      end;
    _ ->
      error
  end;
parse(_) ->
  error.

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

service(#rtsp_message{method = 'OPTIONS'} = _Message) ->
  % Ответ с перечнем доступных методов
  SupportedMethods = <<"OPTIONS, DESCRIBE, SETUP, PLAY, PAUSE, TEARDOWN">>,
  io:format("Handling OPTIONS request~n"),
  <<"RTSP/1.0 200 OK\r\nPublic: ", SupportedMethods/binary, "\r\n\r\n">>;

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
    "o=lubitelkvokk ", SessionIdBinary/binary, " IN IP4 127.0.0.1\r\n",
    "s=SDP Seminar\r\n",
    "i=RTSP Erlang server\r\n",
    "u=http://www.additional.info.com\r\n",
    "e=pasha110.mikhailov@yandex.ru\r\n",
    "c=IN IP4 127.0.0.1\r\n",
    "t=0 0\r\n",
    "a=recvonly\r\n",
    "m=audio 5004 RTP/AVP 97\r\n",
    "a=rtpmap:97 MPEG4-GENERIC/48000\r\n",
    "a=fmtp:97 streamtype=5; profile-level-id=1; mode=AAC-hbr\r\n",
    "m=video 5006 RTP/AVP 98\r\n",
    "a=rtpmap:98 H265/90000\r\n",
    "\r\n">>,

  % Рассчитываем длину тела сообщения
  ContentLength = integer_to_binary(byte_size(SDP)),
  % Формируем полный ответ
  Response = <<"RTSP/1.0 200 OK\r\n",
    "CSeq: ", CSeq/binary, "\r\n",
    "Content-Type: application/sdp\r\n",
    "Content-Length: ", ContentLength/binary, "\r\n",
    "\r\n",
    SDP/binary>>,

  Response;
service(#rtsp_message{method = 'SETUP', uri = URI} = _Message) ->
  % Пример обработки SETUP-запроса
  io:format("Handling SETUP request for ~s~n", [URI]),
  <<"RTSP/1.0 200 OK\r\nSession: 12345678\r\n\r\n">>;

service(#rtsp_message{method = 'PLAY', uri = URI} = _Message) ->
  % Пример обработки PLAY-запроса
  io:format("Handling PLAY request for ~s~n", [URI]),
  <<"RTSP/1.0 200 OK\r\nRTP-Info: url=rtsp://example.com/trackID=1\r\n\r\n">>;

service(#rtsp_message{method = Method}) ->
  io:format("Unknown method: ~s~n", [Method]),
  <<"RTSP/1.0 501 Not Implemented\r\n\r\n">>.

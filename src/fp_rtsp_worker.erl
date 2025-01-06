%%%-------------------------------------------------------------------
%%% @author Alex
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. янв. 2025 16:28
%%%-------------------------------------------------------------------
-module(fp_rtsp_worker).

-export([loop/1]).
-record(rtsp_message, {
  method,          % Метод запроса: START, DESCRIBE, SETUP и т.д.
  uri,             % URI, на который направлен запрос
  version,         % Версия протокола, например, RTSP/1.0
  headers = #{},   % Заголовки в формате Map
  body = <<>>      % Тело сообщения (может быть пустым)
}).

loop(Socket) ->
  case gen_tcp:recv(Socket, 0) of
    {ok, Data} ->
      case catch parse(Data) of
        {'EXIT', _} ->
          io:format("Failed to parse RTSP message~n"),
          gen_tcp:send(Socket, <<"RTSP/1.0 400 Bad Request\r\n\r\n">>),
          loop(Socket);
        Message ->
          Response = service(Message),
          gen_tcp:send(Socket, Response),
          loop(Socket)
      end;
    {error, closed} ->
      io:format("Client disconnected~n"),
      ok
  end.



parse(Data) ->
  % Разбиваем данные на строки
  [RequestLine | Rest] = binary:split(Data, <<"\r\n">>, [global]),
  % Проверяем, содержит ли первая строка 3 компонента
  case binary:split(RequestLine, <<" ">>) of
    [Method, URI, Version] ->
      % Отделяем заголовки от тела
      {HeadersBin, Body} = lists:foldl(fun parse_line/2, {[], <<>>}, Rest),
      Headers = parse_headers(HeadersBin),
      % Возвращаем заполненный record
      #rtsp_message{
        method = binary_to_existing_atom(Method, utf8),
        uri = URI,
        version = Version,
        headers = Headers,
        body = Body
      };
    _ ->
      io:format("Malformed request line: ~p~n", [RequestLine]),
      error
  end.

% Разбор заголовков
parse_line(<<>>, {Headers, Body}) ->
  {lists:reverse(Headers), Body};
parse_line(Line, {Headers, _Body}) when Line =/= <<>> ->
  {[Line | Headers], <<>>}.

% Преобразование заголовков в Map
parse_headers(Lines) ->
  lists:foldl(fun(Line, Acc) ->
    case binary:split(Line, <<": ">>) of
      [Key, Value] -> maps:put(Key, Value, Acc);
      _ -> Acc
    end
              end, #{}, Lines).

service(#rtsp_message{method = 'OPTIONS'}) ->
  % Ответ с перечнем доступных методов
  SupportedMethods = <<"OPTIONS, DESCRIBE, SETUP, PLAY">>,
  io:format("Handling OPTIONS request~n"),
  <<"RTSP/1.0 200 OK\r\nPublic: ", SupportedMethods/binary, "\r\n\r\n">>;

service(#rtsp_message{method = 'DESCRIBE', uri = URI} = Message) ->
  % Пример обработки DESCRIBE-запроса
  io:format("Handling DESCRIBE request for ~s~n", [URI]),
  <<"RTSP/1.0 200 OK\r\nContent-Type: application/sdp\r\n\r\nSession Description">>;

service(#rtsp_message{method = 'SETUP', uri = URI} = Message) ->
  % Пример обработки SETUP-запроса
  io:format("Handling SETUP request for ~s~n", [URI]),
  <<"RTSP/1.0 200 OK\r\nSession: 12345678\r\n\r\n">>;

service(#rtsp_message{method = 'PLAY', uri = URI} = Message) ->
  % Пример обработки PLAY-запроса
  io:format("Handling PLAY request for ~s~n", [URI]),
  <<"RTSP/1.0 200 OK\r\nRTP-Info: url=rtsp://example.com/trackID=1\r\n\r\n">>;

service(#rtsp_message{method = Method}) ->
  io:format("Unknown method: ~s~n", [Method]),
  <<"RTSP/1.0 501 Not Implemented\r\n\r\n">>.

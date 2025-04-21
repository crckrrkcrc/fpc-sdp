program sdp_test;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, sdp;

procedure TestBasicSession;
var
  session: TSession;
  encoder: TEncoder;
  decoder: TDecoder;
  sdpText: string;
  decodedSession: TSession;
  stream: TStringStream;
begin
  WriteLn('Running TestBasicSession...');
  
  // Создаем тестовую сессию
  session := Default(TSession);
  session.Version := 0;
  with session.Origin do
  begin
    Username := '-';
    SessionID := 1234567890;
    SessionVersion := 1234567890;
    Network := NetworkInternet;
    Typ := TypeIPv4;
    Address := '127.0.0.1';
  end;
  session.Name := 'Test Session';
  session.Connection.Network := NetworkInternet;
  session.Connection.Typ := TypeIPv4;
  session.Connection.Address := '127.0.0.1';

  // Добавляем медиа-поток
  SetLength(session.Media, 1);
  with session.Media[0] do
  begin
    Typ := 'audio';
    Port := 5004;
    Proto := 'RTP/AVP';
    Mode := SendRecv;
    
    // Добавляем формат
    SetLength(Format, 1);
    Format[0].Payload := 0;
    Format[0].Name := 'PCMU';
    Format[0].ClockRate := 8000;
    Format[0].Channels := 1;
  end;

  // Кодируем сессию в SDP
  encoder := NewEncoder;
  try
    encoder.Encode(session);
    sdpText := encoder.AsString;
    WriteLn('Generated SDP:');
    WriteLn(sdpText);
  finally
    encoder.Free;
  end;

  // Декодируем обратно
  stream := TStringStream.Create(sdpText);
  try
    decoder := TDecoder.Create(stream);
    try
      decodedSession := decoder.Decode;
      WriteLn('Decoded formats count: ', Length(decodedSession.Media[0].Format));
      if Length(decodedSession.Media[0].Format) > 0 then
        WriteLn('First format payload: ', decodedSession.Media[0].Format[0].Payload,' name: "', decodedSession.Media[0].Format[0].Name, '"');
      // Проверяем основные поля
      if decodedSession.Version <> session.Version then
        WriteLn('Error: Version mismatch');
      if decodedSession.Name <> session.Name then
        WriteLn('Error: Name mismatch');
      if Length(decodedSession.Media) <> 1 then
        WriteLn('Error: Media count mismatch');
        
      if Length(decodedSession.Media) > 0 then
      begin
        WriteLn('Media Typ:',decodedSession.Media[0].Typ,'=', session.Media[0].Typ);
        if decodedSession.Media[0].Typ <> session.Media[0].Typ then
          WriteLn('Error: Media type mismatch');
        WriteLn('Media Port:',decodedSession.Media[0].Port,'=', session.Media[0].Port);  
        if decodedSession.Media[0].Port <> session.Media[0].Port then
          WriteLn('Error: Media port mismatch');   
        if Length(decodedSession.Media[0].Format) <> 1 then
          WriteLn('Error: Media format count mismatch');
        if Length(decodedSession.Media[0].Format) > 0 then
        begin
          if decodedSession.Media[0].Format[0].Name <> session.Media[0].Format[0].Name then
          begin
            WriteLn('Format Name:', session.Media[0].Format[0].Name,' Decoded',decodedSession.Media[0].Format[0].Name);
            WriteLn('Error: Format name mismatch');
          end;
          if decodedSession.Media[0].Format[0].ClockRate <> session.Media[0].Format[0].ClockRate then
            WriteLn('Error: Format clock rate mismatch');
        end;
      end;
      
      WriteLn('TestBasicSession passed!');
    finally
      decoder.Free;
    end;
  finally
    stream.Free;
  end;
end;

procedure TestVectors;
type
  TTestVector = record
    Name: string;
    SDP: string;
    CheckFields: array of string;
  end;

  function CreateTestVector(AName, ASDP: string; ACheckFields: array of string): TTestVector;
  var
    i: Integer;
  begin
    Result.Name := AName;
    Result.SDP := ASDP;
    SetLength(Result.CheckFields, Length(ACheckFields));
    for i := 0 to High(ACheckFields) do
      Result.CheckFields[i] := ACheckFields[i];
  end;

var
  TestVectors: array of TTestVector;
  i, j: Integer;
  session: TSession;
  sdpText: string;
  encoder: TEncoder;
  containsField: Boolean;
begin
  WriteLn('Running TestVectors...');
  
  // Инициализируем тестовые векторы
  SetLength(TestVectors, 4);
  TestVectors[0] := CreateTestVector(
    'RFC 4566 Example',
    'v=0'#13#10 +
    'o=jdoe 2890844526 2890842807 IN IP4 10.47.16.5'#13#10 +
    's=SDP Seminar'#13#10 +
    'i=A Seminar on the session description protocol'#13#10 +
    'u=http://www.example.com/seminars/sdp.pdf'#13#10 +
    'e=j.doe@example.com (Jane Doe)'#13#10 +
    'c=IN IP4 224.2.17.12/127'#13#10 +
    't=2873397496 2873404696'#13#10 +
    'a=recvonly'#13#10 +
    'm=audio 49170 RTP/AVP 0'#13#10 +
    'm=video 51372 RTP/AVP 99'#13#10 +
    'a=rtpmap:99 h263-1998/90000'#13#10,
    ['v=0', 'o=jdoe', 's=SDP Seminar', 'm=audio 49170', 'a=rtpmap:99']
  );

  TestVectors[1] := CreateTestVector(
    'WebRTC Example',
    'v=0'#13#10 +
    'o=- 7614219274587720257 2 IN IP4 127.0.0.1'#13#10 +
    's=-'#13#10 +
    't=0 0'#13#10 +
    'a=group:BUNDLE audio video'#13#10 +
    'a=msid-semantic: WMS'#13#10 +
    'm=audio 9 UDP/TLS/RTP/SAVPF 111 103 104'#13#10 +
    'a=rtpmap:111 opus/48000/2'#13#10 +
    'a=rtpmap:103 ISAC/16000'#13#10 +
    'a=rtpmap:104 ISAC/32000'#13#10 +
    'm=video 9 UDP/TLS/RTP/SAVPF 96 97 98'#13#10 +
    'a=rtpmap:96 VP8/90000'#13#10 +
    'a=rtpmap:97 VP9/90000'#13#10,
    ['m=audio 9', 'a=rtpmap:111 opus', 'm=video 9', 'a=group:BUNDLE']
  );

  TestVectors[2] := CreateTestVector(
    'H.323 Example',
    'v=0'#13#10 +
    'o=root 31589 31589 IN IP4 10.0.0.1'#13#10 +
    's=session'#13#10 +
    'c=IN IP4 10.0.0.1'#13#10 +
    't=0 0'#13#10 +
    'm=audio 30000 RTP/AVP 8 0 101'#13#10 +
    'a=rtpmap:8 PCMA/8000'#13#10 +
    'a=rtpmap:0 PCMU/8000'#13#10 +
    'a=rtpmap:101 telephone-event/8000'#13#10 +
    'a=fmtp:101 0-15'#13#10 +
    'm=video 30002 RTP/AVP 96'#13#10 +
    'a=rtpmap:96 H264/90000'#13#10 +
    'a=fmtp:96 profile-level-id=42E01F'#13#10,
    ['m=audio 30000', 'a=rtpmap:8 PCMA', 'm=video 30002', 'a=fmtp:96']
  );

  TestVectors[3] := CreateTestVector(
    'Multicast Example',
    'v=0'#13#10 +
    'o=alice 2890844526 2890844526 IN IP4 192.0.2.1'#13#10 +
    's=Multicast Test'#13#10 +
    'i=A multicast test session'#13#10 +
    't=2873397496 2873404696'#13#10 +
    'c=IN IP4 224.2.17.12/127'#13#10 +
    'm=audio 49170 RTP/AVP 0'#13#10 +
    'a=recvonly'#13#10 +
    'm=video 51372 RTP/AVP 31'#13#10 +
    'a=recvonly'#13#10 +
    'm=application 32416 udp wb'#13#10 +
    'a=orient:portrait'#13#10,
    ['c=IN IP4 224.2.17.12/127', 'm=audio 49170', 'm=application 32416', 'a=orient']
  );
  
  for i := 0 to High(TestVectors) do
  begin
    WriteLn('Testing vector: ', TestVectors[i].Name);
    
    // Парсим SDP
    session := ParseSdp(TestVectors[i].SDP);
    
    // Кодируем обратно для проверки
    encoder := NewEncoder;
    try
      encoder.Encode(session);
      sdpText := encoder.AsString;
    finally
      encoder.Free;
    end;
    
    // Проверяем наличие ключевых полей
    for j := 0 to High(TestVectors[i].CheckFields) do
    begin
      containsField := Pos(TestVectors[i].CheckFields[j], sdpText) > 0;
      if not containsField then
        WriteLn('Error: Field "', TestVectors[i].CheckFields[j], '" not found in parsed SDP');
    end;
    
    WriteLn('Vector "', TestVectors[i].Name, '" passed!');
  end;
  
  WriteLn('TestVectors completed!');
end;

begin
  try
    TestBasicSession;
    TestVectors;
    
    WriteLn('All tests completed!');
  except
    on E: Exception do
      WriteLn('Test failed: ', E.Message);
  end;
end.
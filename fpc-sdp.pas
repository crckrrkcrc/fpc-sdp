unit fpc-sdp;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, DateUtils, StrUtils;

const
  ContentType = 'application/sdp';
  NetworkInternet = 'IN';
  TypeIPv4 = 'IP4';
  TypeIPv6 = 'IP6';

  SendRecv = 'sendrecv';
  SendOnly = 'sendonly';
  RecvOnly = 'recvonly';
  Inactive = 'inactive';

type
  TAttr = record
    Name: string;
    Value: string;
  end;
  TAttributes = array of TAttr;
  
  TOrigin = record
    Username: string;
    SessionID: Int64;
    SessionVersion: Int64;
    Network: string;
    Typ: string;
    Address: string;
  end;

  TConnection = record
    Network: string;
    Typ: string;
    Address: string;
    TTL: Integer;
    AddressNum: Integer;
  end;
  TConnections = array of TConnection;

  TBandwidth = record
    Typ: string;
    Value: Integer;
  end;
  TBandwidths = array of TBandwidth;

  TTimeZone = record
    Time: TDateTime;
    Offset: Int64;
  end;
  TTimeZones = array of TTimeZone;

  TKey = record
    Method: string;
    Value: string;
  end;
  TKeys = array of TKey;

  TTiming = record
    Start: TDateTime;
    Stop: TDateTime;
  end;

  TRepeatTimes = record
    Interval: Int64;
    Duration: Int64;
    Offsets: array of Int64;
  end;
  TRepeats = array of TRepeatTimes;

  TFormat = record
    Payload: Byte;
    Name: string;
    ClockRate: Integer;
    Channels: Integer;
    Feedback: array of string;
    Params: array of string;
  end;
  TFormats = array of TFormat;

  TMedia = record
    Typ: string;
    Port: Integer;
    PortNum: Integer;
    Proto: string;
    Information: string;
    Connection: TConnections;
    Bandwidth: TBandwidths;
    Key: TKeys;
    Attributes: TAttributes;
    Mode: string;
    Format: TFormats;
    FormatDescr: string;
  end;
  TMedias = array of TMedia;

  TSession = record
    Version: Integer;
    Origin: TOrigin;
    Name: string;
    Information: string;
    URI: string;
    Email: array of string;
    Phone: array of string;
    Connection: TConnection;
    Bandwidth: TBandwidths;
    TimeZone: TTimeZones;
    Key: TKeys;
    Timing: TTiming;
    RepeatTimes: TRepeats;
    Attributes: TAttributes;
    Mode: string;
    Media: TMedias;
  end;

  TLineReader = class
  private
    FStream: TStream;
  public
    constructor Create(AStream: TStream);
    function ReadLine: string;
  end;
  
  ESdpError = class(Exception);
  ESdpDecodeError = class(ESdpError)
  public
    Line: Integer;
    Text: string;
    constructor Create(AError: string; ALine: Integer; AText: string);
  end;

  TEncoder = class
  private
    FWriter: TStream;
    FBuffer: TBytes;
    FBufferPos: Integer;
    procedure WriteChar(c: Char);
    procedure WriteStr(const s: string);
    procedure WriteInt(v: Int64);
    procedure WriteFields(const fields: array of string);
    procedure WriteTransport(network, typ, addr: string);
    procedure WriteDuration(d: Int64);
    procedure WriteTime(t: TDateTime);
  public
    constructor Create(AWriter: TStream; BufferSize: Integer = 1024);
    procedure Reset;
    function Encode(const S: TSession): Boolean;
    procedure Flush;
    function GetBytes: TBytes;
    function AsString: string;
  end;

  TDecoder = class
  private
    FReader: TLineReader;
    FLineNum: Integer;
    function ParseOrigin(const V: string): TOrigin;
    function ParseConnection(const V: string): TConnection;
    function ParseBandwidth(const V: string): TBandwidth;
    function ParseTimeZone(const V: string): TTimeZones;
    function ParseKey(const V: string): TKey;
    function ParseAttr(const V: string): TAttr;
    function ParseTiming(const V: string): TTiming;
    function ParseRepeat(const V: string): TRepeatTimes;
    function ParseTime(const V: string): TDateTime;
    function ParseDuration(const V: string): Int64;
    function ParseInt(const V: string): Int64;
    function SplitFields(const S: string; Sep: Char; Count: Integer): TStringArray;
    procedure ParseRtpMap(var F: TFormat; const V: string);
    procedure ParseMediaFormat(M: TMedia; A: TAttr);
    procedure ParseMediaProto(var M: TMedia; const V: string);
  public
    constructor Create(AReader: TStream);
    destructor Destroy; override;
    function Decode: TSession;
    procedure DecodeSession(var S: TSession; F: Char; const V: string);
    procedure DecodeMedia(var M: TMedia; F: Char; const V: string);
  end;

function NewAttr(Attr, Value: string): TAttr;
function NewAttrFlag(Flag: string): TAttr;
function AttrToString(const A: TAttr): string;
function AttributesHas(const A: TAttributes; Name: string): Boolean;
function AttributesGet(const A: TAttributes; Name: string): string;
function DeleteAttr(var Attrs: TAttributes; const Names: array of string): TAttributes;

function MediaFormatByPayload(const M: TMedia; Payload: Byte): TFormat;
function IsRTP(const Media, Proto: string): Boolean;

function NegotiateMode(const Local, Remote: string): string;

function SessionToString(const S: TSession): string;
function SessionToBytes(const S: TSession): TBytes;
function ParseSdp(const Data: string): TSession;
function ParseSdpFromStream(Stream: TStream): TSession;

function NewEncoder(AWriter: TStream): TEncoder; overload;
function NewEncoder: TEncoder; overload;

implementation

var
  Epoch: TDateTime;

{ ESdpDecodeError }

constructor ESdpDecodeError.Create(AError: string; ALine: Integer; AText: string);
begin
  inherited CreateFmt('SDP: %s on line %d "%s"', [AError, ALine, AText]);
  Line := ALine;
  Text := AText;
end;

{ TLineReader }

constructor TLineReader.Create(AStream: TStream);
begin
  FStream := AStream;
end;

function TLineReader.ReadLine: string;
var
  C: AnsiChar;
  BytesRead: Integer;
begin
  Result := '';
  BytesRead := FStream.Read(C, 1);
  
  while (BytesRead > 0) and (C <> #10) do
  begin
    if C <> #13 then
      Result := Result + C;
    BytesRead := FStream.Read(C, 1);
  end;
end;

{ TEncoder }

constructor TEncoder.Create(AWriter: TStream; BufferSize: Integer);
begin
  FWriter := AWriter;
  SetLength(FBuffer, BufferSize);
  FBufferPos := 0;
end;

procedure TEncoder.Reset;
begin
  FBufferPos := 0;
end;

procedure TEncoder.WriteChar(c: Char);
begin
  if FBufferPos >= Length(FBuffer) then
    SetLength(FBuffer, Length(FBuffer) * 2);
  FBuffer[FBufferPos] := Byte(c);
  Inc(FBufferPos);
end;

procedure TEncoder.WriteStr(const s: string);
var
  i: Integer;
begin
  if s = '' then
    WriteChar('-')
  else
    for i := 1 to Length(s) do
      WriteChar(s[i]);
end;

procedure TEncoder.WriteInt(v: Int64);
begin
  WriteStr(IntToStr(v));
end;

procedure TEncoder.WriteFields(const fields: array of string);
var
  i: Integer;
begin
  for i := 0 to High(fields) do
  begin
    if i > 0 then WriteChar(' ');
    WriteStr(fields[i]);
  end;
end;

procedure TEncoder.WriteTransport(network, typ, addr: string);
begin
  if network = '' then network := NetworkInternet;
  if typ = '' then typ := TypeIPv4;
  if addr = '' then addr := '127.0.0.1';
  WriteFields([network, typ, addr]);
end;

procedure TEncoder.WriteDuration(d: Int64);
var
  sec: Int64;
begin
  sec := d div 1000;
  case sec of
    0: WriteChar('0');
    else if sec mod 86400 = 0 then begin
      WriteInt(sec div 86400);
      WriteChar('d');
    end
    else if sec mod 3600 = 0 then begin
      WriteInt(sec div 3600);
      WriteChar('h');
    end
    else if sec mod 60 = 0 then begin
      WriteInt(sec div 60);
      WriteChar('m');
    end
    else begin
      WriteInt(sec);
    end;
  end;
end;

procedure TEncoder.WriteTime(t: TDateTime);
begin
  if t = 0 then
    WriteChar('0')
  else
    WriteInt(SecondsBetween(Epoch, t));
end;

function TEncoder.Encode(const S: TSession): Boolean;
var
  i, j, k: Integer;
begin
  Reset;

  // Protocol Version
  WriteStr('v='); WriteInt(S.Version);

  // Origin
  WriteStr(#13#10'o=');
  with S.Origin do
  begin
    WriteStr(Username); WriteChar(' ');
    WriteInt(SessionID); WriteChar(' ');
    WriteInt(SessionVersion); WriteChar(' ');
    WriteTransport(Network, Typ, Address);
  end;

  // Session Name
  WriteStr(#13#10's='); WriteStr(S.Name);

  // Session Information
  if S.Information <> '' then
  begin
    WriteStr(#13#10'i='); WriteStr(S.Information);
  end;

  // URI
  if S.URI <> '' then
  begin
    WriteStr(#13#10'u='); WriteStr(S.URI);
  end;

  // Email
  for i := 0 to High(S.Email) do
  begin
    WriteStr(#13#10'e='); WriteStr(S.Email[i]);
  end;

  // Phone
  for i := 0 to High(S.Phone) do
  begin
    WriteStr(#13#10'p='); WriteStr(S.Phone[i]);
  end;

  // Connection Data
  if (S.Connection.Network <> '') or (S.Connection.Typ <> '') or (S.Connection.Address <> '') then
  begin
    WriteStr(#13#10'c=');
    with S.Connection do
    begin
      WriteTransport(Network, Typ, Address);
      if TTL > 0 then
      begin
        WriteChar('/'); WriteInt(TTL);
      end;
      if AddressNum > 1 then
      begin
        WriteChar('/'); WriteInt(AddressNum);
      end;
    end;
  end;

  // Bandwidth
  for i := 0 to High(S.Bandwidth) do
  begin
    WriteStr(#13#10'b=');
    with S.Bandwidth[i] do
    begin
      WriteStr(Typ); WriteChar(':'); WriteInt(Value);
    end;
  end;

  // Timing
  WriteStr(#13#10't=');
  with S.Timing do
  begin
    WriteTime(Start); WriteChar(' '); WriteTime(Stop);
  end;

  // Repeat Times
  for i := 0 to High(S.RepeatTimes) do
  begin
    WriteStr(#13#10'r=');
    with S.RepeatTimes[i] do
    begin
      WriteDuration(Interval); WriteChar(' ');
      WriteDuration(Duration);
      for j := 0 to High(Offsets) do
      begin
        WriteChar(' '); WriteDuration(Offsets[j]);
      end;
    end;
  end;

  // Time Zones
  if Length(S.TimeZone) > 0 then
  begin
    WriteStr(#13#10'z=');
    for i := 0 to High(S.TimeZone) do
    begin
      if i > 0 then WriteChar(' ');
      with S.TimeZone[i] do
      begin
        WriteTime(Time); WriteChar(' '); WriteDuration(Offset);
      end;
    end;
  end;

  // Encryption Keys
  for i := 0 to High(S.Key) do
  begin
    WriteStr(#13#10'k=');
    with S.Key[i] do
    begin
      if Value = '' then
        WriteStr(Method)
      else
      begin
        WriteStr(Method); WriteChar(':'); WriteStr(Value);
      end;
    end;
  end;

  // Session Attributes
  if S.Mode <> '' then
  begin
    WriteStr(#13#10'a='); WriteStr(S.Mode);
  end;

  for i := 0 to High(S.Attributes) do
  begin
    WriteStr(#13#10'a=');
    with S.Attributes[i] do
    begin
      if Value = '' then
        WriteStr(Name)
      else
      begin
        WriteStr(Name); WriteChar(':'); WriteStr(Value);
      end;
    end;
  end;

  // Media Descriptions
  for i := 0 to High(S.Media) do
  begin
    WriteStr(#13#10'm=');
    with S.Media[i] do
    begin
      WriteStr(Typ); WriteChar(' ');
      WriteInt(Port);
      if PortNum > 0 then
      begin
        WriteChar('/'); WriteInt(PortNum);
      end;
      WriteChar(' '); WriteStr(Proto);
      
      // Format Description
      if FormatDescr <> '' then
      begin
        WriteChar(' '); WriteStr(FormatDescr);
      end
      else if Length(Format) > 0 then
      begin
        for j := 0 to High(Format) do
        begin
          WriteChar(' '); WriteInt(Format[j].Payload);
        end;
      end
      else if PortNum = 0 then
      begin
        WriteChar(' '); WriteStr('0');
      end;

      // Media Information
      if Information <> '' then
      begin
        WriteStr(#13#10'i='); WriteStr(Information);
      end;

      // Media Connection
      for j := 0 to High(Connection) do
      begin
        WriteStr(#13#10'c=');
        with Connection[j] do
        begin
          WriteTransport(Network, Typ, Address);
          if TTL > 0 then
          begin
            WriteChar('/'); WriteInt(TTL);
          end;
          if AddressNum > 1 then
          begin
            WriteChar('/'); WriteInt(AddressNum);
          end;
        end;
      end;

      // Media Bandwidth
      for j := 0 to High(Bandwidth) do
      begin
        WriteStr(#13#10'b=');
        with Bandwidth[j] do
        begin
          WriteStr(Typ); WriteChar(':'); WriteInt(Value);
        end;
      end;

      // Media Keys
      for j := 0 to High(Key) do
      begin
        WriteStr(#13#10'k=');
        with Key[j] do
        begin
          if Value = '' then
            WriteStr(Method)
          else
          begin
            WriteStr(Method); WriteChar(':'); WriteStr(Value);
          end;
        end;
      end;

      // Media Formats
      for j := 0 to High(Format) do
      begin
        // rtpmap
        if (Format[j].Name <> '') then
        begin
          WriteStr(#13#10'a=rtpmap:'); WriteInt(Format[j].Payload); WriteChar(' ');
          WriteStr(Format[j].Name); WriteChar('/'); WriteInt(Format[j].ClockRate);
          if Format[j].Channels > 1 then
          begin
            WriteChar('/'); WriteInt(Format[j].Channels);
          end;
        end;

        // rtcp-fb
        for k := 0 to High(Format[j].Feedback) do
        begin
          WriteStr(#13#10'a=rtcp-fb:'); WriteInt(Format[j].Payload); WriteChar(' ');
          WriteStr(Format[j].Feedback[k]);
        end;

        // fmtp
        for k := 0 to High(Format[j].Params) do
        begin
          WriteStr(#13#10'a=fmtp:'); WriteInt(Format[j].Payload); WriteChar(' ');
          WriteStr(Format[j].Params[k]);
        end;
      end;

      // Media Mode
      if Mode <> '' then
      begin
        WriteStr(#13#10'a='); WriteStr(Mode);
      end;

      // Media Attributes
      for j := 0 to High(Attributes) do
      begin
        WriteStr(#13#10'a=');
        if Attributes[j].Value = '' then
          WriteStr(Attributes[j].Name)
        else
        begin
          WriteStr(Attributes[j].Name); WriteChar(':'); WriteStr(Attributes[j].Value);
        end;
      end;
    end;
  end;

  // Final CRLF
  WriteStr(#13#10);

  Result := True;
end;

procedure TEncoder.Flush;
begin
  if (FWriter <> nil) and (FBufferPos > 0) then
  begin
    FWriter.WriteBuffer(FBuffer[0], FBufferPos);
    FBufferPos := 0;
  end;
end;

function TEncoder.GetBytes: TBytes;
begin
  SetLength(Result, FBufferPos);
  if FBufferPos > 0 then
    Move(FBuffer[0], Result[0], FBufferPos);
end;

function TEncoder.AsString: string;
begin
  SetString(Result, PChar(@FBuffer[0]), FBufferPos);
end;

{ TDecoder }

constructor TDecoder.Create(AReader: TStream);
begin
  FReader := TLineReader.Create(AReader);
  FLineNum := 0;
end;

destructor TDecoder.Destroy;
begin
  FReader.Free;
  inherited Destroy;
end;

function TDecoder.Decode: TSession;
var
  Line: string;
  CurrentMedia: TMedia;
begin
  Result := Default(TSession);
  CurrentMedia := Default(TMedia);

  while True do
  begin
    Inc(FLineNum);
    Line := FReader.ReadLine;
    
    // Конец данных
    if (Line = '') and (Result.Origin.Username <> '') then
      Break;
      
    // Пустые строки пропускаем
    if Line = '' then
      Continue;
      
    // Проверяем формат строки (должна быть "x=value")
    if (Length(Line) < 2) or (Line[2] <> '=') then
      raise ESdpDecodeError.Create('Invalid format', FLineNum, Line);
      
    try
      if Line[1] = 'm' then
      begin
        // Новая медиа-секция
        CurrentMedia := Default(TMedia);
        SetLength(Result.Media, Length(Result.Media) + 1);
        Result.Media[High(Result.Media)] := CurrentMedia;
        DecodeMedia(Result.Media[High(Result.Media)], Line[1], Copy(Line, 3, MaxInt));
      end
      else if Length(Result.Media) > 0 then
      begin
        // Поле медиа-секции
        DecodeMedia(Result.Media[High(Result.Media)], Line[1], Copy(Line, 3, MaxInt));
      end
      else
      begin
        // Поле сессии
        DecodeSession(Result, Line[1], Copy(Line, 3, MaxInt));
      end;
    except
      on E: Exception do
        raise ESdpDecodeError.Create(E.Message, FLineNum, Line);
    end;
  end;
end;

procedure TDecoder.DecodeSession(var S: TSession; F: Char; const V: string);
var
  I: Int64;
begin
  case F of
    'v': S.Version := StrToInt(V);
    'o': S.Origin := ParseOrigin(V);
    's': S.Name := V;
    'i': S.Information := V;
    'u': S.URI := V;
    'e': 
      begin
        SetLength(S.Email, Length(S.Email) + 1);
        S.Email[High(S.Email)] := V;
      end;
    'p':
      begin
        SetLength(S.Phone, Length(S.Phone) + 1);
        S.Phone[High(S.Phone)] := V;
      end;
    'c': S.Connection := ParseConnection(V);
    'b':
      begin
        SetLength(S.Bandwidth, Length(S.Bandwidth) + 1);
        S.Bandwidth[High(S.Bandwidth)] := ParseBandwidth(V);
      end;
    'z': S.TimeZone := ParseTimeZone(V);
    'k':
      begin
        SetLength(S.Key, Length(S.Key) + 1);
        S.Key[High(S.Key)] := ParseKey(V);
      end;
    'a':
      begin
        if (V = Inactive) or (V = RecvOnly) or (V = SendOnly) or (V = SendRecv) then
          S.Mode := V
        else
        begin
          SetLength(S.Attributes, Length(S.Attributes) + 1);
          S.Attributes[High(S.Attributes)] := ParseAttr(V);
        end;
      end;
    't': S.Timing := ParseTiming(V);
    'r':
      begin
        SetLength(S.RepeatTimes, Length(S.RepeatTimes) + 1);
        S.RepeatTimes[High(S.RepeatTimes)] := ParseRepeat(V);
      end;
  else
    raise ESdpError.Create('Unexpected field');
  end;
end;

procedure TDecoder.DecodeMedia(var M: TMedia; F: Char; const V: string);
var
  Attr: TAttr;
begin
  case F of
    'm': ParseMediaProto(M, V);
    'i': M.Information := V;
    'c':
      begin
        SetLength(M.Connection, Length(M.Connection) + 1);
        M.Connection[High(M.Connection)] := ParseConnection(V);
      end;
    'b':
      begin
        SetLength(M.Bandwidth, Length(M.Bandwidth) + 1);
        M.Bandwidth[High(M.Bandwidth)] := ParseBandwidth(V);
      end;
    'k':
      begin
        SetLength(M.Key, Length(M.Key) + 1);
        M.Key[High(M.Key)] := ParseKey(V);
      end;
    'a':
      begin
        if (V = Inactive) or (V = RecvOnly) or (V = SendOnly) or (V = SendRecv) then
          M.Mode := V
        else
        begin
          Attr := ParseAttr(V);
          if (Attr.Name = 'rtpmap') or (Attr.Name = 'fmtp') or (Attr.Name = 'rtcp-fb') then
            ParseMediaFormat(M, Attr)
          else
          begin
            SetLength(M.Attributes, Length(M.Attributes) + 1);
            M.Attributes[High(M.Attributes)] := Attr;
          end;
        end;
      end;
  else
    raise ESdpError.Create('Unexpected field');
  end;
end;

function TDecoder.ParseOrigin(const V: string): TOrigin;
var
  Parts: TStringArray;
begin
  Parts := SplitFields(V, ' ', 6);
  if Length(Parts) <> 6 then
    raise ESdpError.Create('Invalid origin format');

  Result.Username := Parts[0];
  Result.SessionID := ParseInt(Parts[1]);
  Result.SessionVersion := ParseInt(Parts[2]);
  Result.Network := Parts[3];
  Result.Typ := Parts[4];
  Result.Address := Parts[5];
end;

function TDecoder.ParseConnection(const V: string): TConnection;
var
  Parts: TStringArray;
begin
  Parts := SplitFields(V, ' ', 3);
  if Length(Parts) < 3 then
    raise ESdpError.Create('Invalid connection format');

  Result.Network := Parts[0];
  Result.Typ := Parts[1];
  Result.Address := Parts[2];
  Result.TTL := 0;
  Result.AddressNum := 1;

  // Parse additional parameters for IPv4/IPv6
  Parts := SplitFields(Result.Address, '/', 3);
  if Result.Typ = TypeIPv4 then
  begin
    if Length(Parts) > 1 then
    begin
      Result.TTL := StrToInt(Parts[1]);
      Result.Address := Parts[0];
    end;
    if Length(Parts) > 2 then
      Result.AddressNum := StrToInt(Parts[2]);
  end
  else if Result.Typ = TypeIPv6 then
  begin
    if Length(Parts) > 1 then
    begin
      Result.AddressNum := StrToInt(Parts[1]);
      Result.Address := Parts[0];
    end;
  end;
end;

function TDecoder.ParseBandwidth(const V: string): TBandwidth;
var
  Parts: TStringArray;
begin
  Parts := SplitFields(V, ':', 2);
  if Length(Parts) <> 2 then
    raise ESdpError.Create('Invalid bandwidth format');

  Result.Typ := Parts[0];
  Result.Value := StrToInt(Parts[1]);
end;

function TDecoder.ParseTimeZone(const V: string): TTimeZones;
var
  Parts, TimeParts: TStringArray;
  I: Integer;
begin
  Parts := SplitFields(V, ' ', MaxInt);
  SetLength(Result, Length(Parts) div 2);
  
  for I := 0 to (Length(Parts) div 2) - 1 do
  begin
    Result[I].Time := ParseTime(Parts[I*2]);
    Result[I].Offset := ParseDuration(Parts[I*2+1]);
  end;
end;

function TDecoder.ParseKey(const V: string): TKey;
var
  Parts: TStringArray;
begin
  Parts := SplitFields(V, ':', 2);
  if Length(Parts) = 1 then
  begin
    Result.Method := Parts[0];
    Result.Value := '';
  end
  else
  begin
    Result.Method := Parts[0];
    Result.Value := Parts[1];
  end;
end;

function TDecoder.ParseAttr(const V: string): TAttr;
var
  PosSep: Integer;
begin
  PosSep := Pos(':', V);
  if PosSep > 0 then
  begin
    Result.Name := Copy(V, 1, PosSep - 1);
    Result.Value := Copy(V, PosSep + 1, Length(V));
  end
  else
  begin
    Result.Name := V;
    Result.Value := '';
  end;
end;

function TDecoder.ParseTiming(const V: string): TTiming;
var
  Parts: TStringArray;
begin
  Parts := SplitFields(V, ' ', 2);
  if Length(Parts) <> 2 then
    raise ESdpError.Create('Invalid timing format');

  Result.Start := ParseTime(Parts[0]);
  Result.Stop := ParseTime(Parts[1]);
end;

function TDecoder.ParseRepeat(const V: string): TRepeatTimes;
var
  Parts: TStringArray;
  I: Integer;
begin
  Parts := SplitFields(V, ' ', MaxInt);
  if Length(Parts) < 2 then
    raise ESdpError.Create('Invalid repeat format');

  Result.Interval := ParseDuration(Parts[0]);
  Result.Duration := ParseDuration(Parts[1]);
  
  if Length(Parts) > 2 then
  begin
    SetLength(Result.Offsets, Length(Parts) - 2);
    for I := 2 to High(Parts) do
      Result.Offsets[I-2] := ParseDuration(Parts[I]);
  end
  else
    SetLength(Result.Offsets, 0);
end;

function TDecoder.ParseTime(const V: string): TDateTime;
var
  Sec: Int64;
begin
  Sec := ParseInt(V);
  if Sec = 0 then
    Result := 0
  else
    Result := IncSecond(Epoch, Sec);
end;

function TDecoder.ParseDuration(const V: string): Int64;
var
  NumStr: string;
  Multiplier: Int64;
begin
  if V = '' then
    Exit(0);

  if V[Length(V)] in ['d', 'h', 'm', 's'] then
  begin
    NumStr := Copy(V, 1, Length(V)-1);
    case V[Length(V)] of
      'd': Multiplier := 86400 * 1000;
      'h': Multiplier := 3600 * 1000;
      'm': Multiplier := 60 * 1000;
      's': Multiplier := 1 * 1000;
    else
      Multiplier := 1000;
    end;
  end
  else
  begin
    NumStr := V;
    Multiplier := 1000;
  end;

  Result := ParseInt(NumStr) * Multiplier;
end;

function TDecoder.ParseInt(const V: string): Int64;
begin
  if not TryStrToInt64(V, Result) then
    raise ESdpError.Create('Invalid integer value');
end;

function TDecoder.SplitFields(const S: string; Sep: Char; Count: Integer): TStringArray;
var
  Start, Index: Integer;
begin
  SetLength(Result, 0);
  Start := 1;
  
  while (Start <= Length(S)) and (Length(Result) < Count) do
  begin
    Index := PosEx(Sep, S, Start);
    if Index = 0 then
      Index := Length(S) + 1;
      
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Copy(S, Start, Index - Start);
    Start := Index + 1;
  end;
end;

procedure TDecoder.ParseRtpMap(var F: TFormat; const V: string);
var
  Parts: TStringArray;
begin
  Parts := SplitFields(V, '/', 3);
  if Length(Parts) < 2 then
    raise ESdpError.Create('Invalid rtpmap format');

  F.Name := Parts[0];
  F.ClockRate := StrToInt(Parts[1]);
  if Length(Parts) > 2 then
    F.Channels := StrToInt(Parts[2])
  else
    F.Channels := 1;
end;

procedure TDecoder.ParseMediaFormat(M: TMedia; A: TAttr);
var
  Parts: TStringArray;
  Payload: Integer;
  F: TFormat;
begin
  // Разбираем атрибут вида "rtpmap:96 H264/90000" или "fmtp:96 profile-level-id=42E01F"
  Parts := SplitFields(A.Value, ' ', 2);
  if Length(Parts) < 2 then
    Exit;

  // Обработка специального значения "*" для всех форматов
  if Parts[0] = '*' then
  begin
    // Пока не реализовано
    Exit;
  end;

  // Обычный payload type
  Payload := StrToInt(Parts[0]);
  
  // Находим или создаем формат
  F := MediaFormatByPayload(M, Payload);
  if F.Payload = 0 then // Not found
  begin
    F.Payload := Payload;
    F.ClockRate := 8000; // Default value
    F.Channels := 1;
    SetLength(M.Format, Length(M.Format) + 1);
    M.Format[High(M.Format)] := F;
  end;

  case A.Name of
    'rtpmap': ParseRtpMap(M.Format[High(M.Format)], Parts[1]);
    'rtcp-fb': 
      begin
        SetLength(M.Format[High(M.Format)].Feedback, Length(M.Format[High(M.Format)].Feedback) + 1);
        M.Format[High(M.Format)].Feedback[High(M.Format[High(M.Format)].Feedback)] := Parts[1];
      end;
    'fmtp':
      begin
        SetLength(M.Format[High(M.Format)].Params, Length(M.Format[High(M.Format)].Params) + 1);
        M.Format[High(M.Format)].Params[High(M.Format[High(M.Format)].Params)] := Parts[1];
      end;
  end;
end;

procedure TDecoder.ParseMediaProto(var M: TMedia; const V: string);
var
  Parts, PortParts: TStringArray;
  I: Integer;
begin
  Parts := SplitFields(V, ' ', 4);
  if Length(Parts) < 3 then
    raise ESdpError.Create('Invalid media format');

  M.Typ := Parts[0];
  
  // Разбираем порт и количество портов
  PortParts := SplitFields(Parts[1], '/', 2);
  M.Port := StrToInt(PortParts[0]);
  if Length(PortParts) > 1 then
    M.PortNum := StrToInt(PortParts[1])
  else
    M.PortNum := 0;

  M.Proto := Parts[2];

  // Форматы
  if Length(Parts) > 3 then
  begin
    if not IsRTP(M.Typ, M.Proto) then
    begin
      M.FormatDescr := Parts[3];
    end
    else
    begin
      PortParts := SplitFields(Parts[3], ' ', MaxInt);
      for I := 0 to High(PortParts) do
      begin
        SetLength(M.Format, Length(M.Format) + 1);
        M.Format[High(M.Format)].Payload := StrToInt(PortParts[I]);
        M.Format[High(M.Format)].ClockRate := 8000; // Default
        M.Format[High(M.Format)].Channels := 1;
      end;
    end;
  end;
end;

// Публичные функции
function NewAttr(Attr, Value: string): TAttr;
begin
  Result.Name := Attr;
  Result.Value := Value;
end;

function NewAttrFlag(Flag: string): TAttr;
begin
  Result.Name := Flag;
  Result.Value := '';
end;

function AttrToString(const A: TAttr): string;
begin
  if A.Value = '' then
    Result := A.Name
  else
    Result := A.Name + ':' + A.Value;
end;

function AttributesHas(const A: TAttributes; Name: string): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(A) do
    if A[i].Name = Name then
      Exit(True);
  Result := False;
end;

function AttributesGet(const A: TAttributes; Name: string): string;
var
  i: Integer;
begin
  for i := 0 to High(A) do
    if A[i].Name = Name then
      Exit(A[i].Value);
  Result := '';
end;

function DeleteAttr(var Attrs: TAttributes; const Names: array of string): TAttributes;
var
  i, j, k: Integer;
  Skip: Boolean;
begin
  j := 0;
  for i := 0 to High(Attrs) do
  begin
    Skip := False;
    for k := Low(Names) to High(Names) do
      if Attrs[i].Name = Names[k] then
      begin
        Skip := True;
        Break;
      end;
    
    if not Skip then
    begin
      if i <> j then
        Attrs[j] := Attrs[i];
      Inc(j);
    end;
  end;
  SetLength(Attrs, j);
  Result := Attrs;
end;

function MediaFormatByPayload(const M: TMedia; Payload: Byte): TFormat;
var
  i: Integer;
begin
  for i := 0 to High(M.Format) do
    if M.Format[i].Payload = Payload then
      Exit(M.Format[i]);
  Result := Default(TFormat);
end;

function IsRTP(const Media, Proto: string): Boolean;
begin
  case Media of
    'audio', 'video':
      Result := (Pos('RTP/AVP', Proto) > 0) or (Pos('RTP/SAVP', Proto) > 0);
    else
      Result := False;
  end;
end;

function NegotiateMode(const Local, Remote: string): string;
begin
  case Local of
    SendRecv, '':
      case Remote of
        RecvOnly: Result := SendOnly;
        SendOnly: Result := RecvOnly;
        else Result := Remote;
      end;
    SendOnly:
      if (Remote = SendRecv) or (Remote = '') or (Remote = RecvOnly) then
        Result := SendOnly
      else
        Result := Inactive;
    RecvOnly:
      if (Remote = SendRecv) or (Remote = '') or (Remote = SendOnly) then
        Result := RecvOnly
      else
        Result := Inactive;
    else
      Result := Inactive;
  end;
end;

function SessionToString(const S: TSession): string;
var
  Encoder: TEncoder;
begin
  Encoder := NewEncoder;
  try
    Encoder.Encode(S);
    Result := Encoder.AsString;
  finally
    Encoder.Free;
  end;
end;

function SessionToBytes(const S: TSession): TBytes;
var
  Encoder: TEncoder;
begin
  Encoder := NewEncoder;
  try
    Encoder.Encode(S);
    Result := Encoder.GetBytes;
  finally
    Encoder.Free;
  end;
end;

function ParseSdp(const Data: string): TSession;
var
  Stream: TStringStream;
begin
  Stream := TStringStream.Create(Data);
  try
    Result := ParseSdpFromStream(Stream);
  finally
    Stream.Free;
  end;
end;

function ParseSdpFromStream(Stream: TStream): TSession;
var
  Decoder: TDecoder;
begin
  Decoder := TDecoder.Create(Stream);
  try
    Result := Decoder.Decode;
  finally
    Decoder.Free;
  end;
end;

function NewEncoder(AWriter: TStream): TEncoder;
begin
  Result := TEncoder.Create(AWriter);
end;

function NewEncoder: TEncoder;
begin
  Result := TEncoder.Create(nil);
end;

initialization
  Epoch := EncodeDate(1900, 1, 1);

end.
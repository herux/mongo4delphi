unit MongoProvider;

interface

{$IFDEF FPC}
  {$DEFINE SYNAPSE}
{$ENDIF}

uses MongoEncoder, MongoDecoder, BSONTypes, BSONStream,
     {$IFDEF SYNAPSE}blcksock,{$ENDIF} Sockets, 
     Classes, SysUtils;

const
  DEFAULT_HOST = 'localhost';
  DEFAULT_PORT = 27017;

type
  IMongoProvider = interface;

  ICommandResult = interface(IBSONObject)
    ['{8F4C1FA8-5CD5-433A-A641-16DA896B42DB}']

    function Ok: Boolean;
    function HasError: Boolean;
    function GetCode: Integer;
    function GetErrorMessage: String;
    function GetException: Exception;
    procedure RaiseOnError;
  end;

  TCommandResult = class(TBSONObject, ICommandResult)
  public
    function HasError: Boolean;
    function Ok: Boolean;
    function GetCode: Integer;
    function GetErrorMessage: String;
    function GetException: Exception;
    procedure RaiseOnError;
  end;

  IWriteResult = interface
    ['{0D69DCD2-60CA-4EA6-9318-6B1EAC69ABE2}']

    function getCachedLastError(): ICommandResult;
    function getLastError(): ICommandResult;
  end;

  TWriteResult = class(TInterfacedObject, IWriteResult)
  private
    FProvider: IMongoProvider;
    FRequestId: Integer;
    FDB: String;
    FLastErrorResult: ICommandResult;
  public
    function getCachedLastError: ICommandResult;
    function getLastError: ICommandResult;

    constructor Create(const AProvider: IMongoProvider; ADB: String; ARequestId: Integer);
  end;

  IMongoProvider = interface
    ['{DBF272FB-59BE-4CA6-B38B-2B1E5879EC34}']

    procedure SetEncoder(const AEncoder: IMongoEncoder);
    procedure SetDecoder(const ADecoder: IMongoDecoder);
        
    procedure Connect(AHost: AnsiString; APort: Integer);
    procedure Close;

    function GetLastError(DB: String; RequestId: Integer=0): ICommandResult;
    function RunCommand(DB: String; Command: IBSONObject): ICommandResult;

    function Insert(DB, Collection: String; BSONObject: IBSONObject): IWriteResult;

    function FindOne(DB, Collection: String; Query: IBSONObject): IBSONObject;

    function OpenQuery(AStream: TBSONStream; DB: String; Collection: String; Query: IBSONObject; ASkip, ABatchSize: Integer): IBSONObject;
    function HasNext(AStream: TBSONStream; DB: String; Collection: String;  ACursorId: Int64; ABatchSize: Integer): IBSONObject;
  end;

  TDefaultMongoProvider = class(TInterfacedObject, IMongoProvider)
  private
    FRequestId: Integer;
    FEncoder: IMongoEncoder;
    FDecoder: IMongoDecoder;
    FQueueRequests: TStringList;
    {$IFDEF SYNAPSE}
    FSocket: TTCPBlockSocket;
    {$ELSE}
    FSocket: TTcpClient;
    {$ENDIF}

    procedure ReadResponse(AStream: TBSONStream; ARequestId: Integer;var AFlags, ANumberReturned: Integer);overload;
    procedure ReadResponse(AStream: TBSONStream; ARequestId: Integer;var AFlags, ANumberReturned: Integer;var ACursorId: Int64);overload;

    function SendBuf(Buffer: Pointer; Length: Integer): Integer;
    function ReceiveBuf(var Buffer; Length: Integer): Integer;

    procedure BeginMsg(AStream: TBSONStream; DB, Collection: String; OperationCode: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    procedure SetEncoder(const AEncoder: IMongoEncoder);
    procedure SetDecoder(const ADecoder: IMongoDecoder);

    procedure Connect(AHost: AnsiString; APort: Integer);
    procedure Close;

    function GetLastError(DB: String; RequestId: Integer=0): ICommandResult;
    function RunCommand(DB: String; Command: IBSONObject): ICommandResult;

    function Insert(DB, Collection: String; BSONObject: IBSONObject): IWriteResult;

    function FindOne(DB, Collection: String; Query: IBSONObject): IBSONObject;
    function OpenQuery(AStream: TBSONStream; DB: String; Collection: String; Query: IBSONObject; ASkip, ABatchSize: Integer): IBSONObject;
    function HasNext(AStream: TBSONStream; DB: String; Collection: String;  ACursorId: Int64; ABatchSize: Integer): IBSONObject;
    //TODO - Assert socket is Connected
  end;

implementation

uses MongoException, Windows, BSON, Variants, Math;

const
  COMMAND_COLLECTION = '$cmd'; 

{ TDefaultMongoProvider }

procedure TDefaultMongoProvider.Close;
begin
  {$IFDEF SYNAPSE}
  FSocket.CloseSocket;
  {$ELSE}
  FSocket.Close;
  {$ENDIF}
end;

constructor TDefaultMongoProvider.Create;
begin
  inherited;

  {$IFDEF SYNAPSE}
  FSocket := TTCPBlockSocket.Create;
  {$ELSE}
  FSocket := TTcpClient.Create(nil);
  {$ENDIF}


  FQueueRequests := TStringList.Create;
end;

destructor TDefaultMongoProvider.Destroy;
begin
  FQueueRequests.Free;
  Close;
  FSocket.Free;
  inherited;
end;

function TDefaultMongoProvider.FindOne(DB, Collection: String; Query: IBSONObject): IBSONObject;
var
  vLength: Integer;
  vStartingFrom: Integer;
  vNumberReturned: Integer;
  vRequestID:integer;
  vResponseTo:integer;
  vOpCode:integer;
  vFlags:integer;
  vCursorId: Int64;
  vStream: TBSONStream;
begin
  InterlockedIncrement(FRequestId);

  vStream := TBSONStream.Create;
  try
    vStream.Clear;
    vStream.WriteInt(0); //length
    vStream.WriteInt(FRequestId);
    vStream.WriteInt(0);//ResponseTo
    vStream.WriteInt(OP_QUERY);
    vStream.WriteInt(0);//Flags
    vStream.WriteUTF8String(Format('%s.%s', [DB, Collection]));
    vStream.WriteInt(0); //NumberToSkip
    vStream.WriteInt(1); //NumberToReturn

    if (Query = nil) then
    begin
      Query := TBSONObject.Create;
    end;

    FEncoder.SetBuffer(vStream);
    FEncoder.Encode(Query);

    vLength := vStream.Size;
    vStream.WriteInt(0, vLength);

    SendBuf(vStream.Memory, vLength);

//    if ReturnFieldSelector<>nil then (ReturnFieldSelector as IPersistStream).Save(FData,false);
    ReadResponse(vStream, FRequestId, vFlags, vNumberReturned, vCursorId);

//    vStream.SaveToFile('Response.stream');

    vStream.Position := 0;
    vStream.Read(vLength, 4);
    vStream.Read(vRequestID, 4);
    vStream.Read(vResponseTo, 4);
    vStream.Read(vOpCode, 4);
    vStream.Read(vFlags, 4);
    vStream.Read(vCursorId, 8);
    vStream.Read(vStartingFrom, 4);
    vStream.Read(vNumberReturned, 4);

    if (vFlags and $0001) <> 0 then
      raise Exception.Create('MongoWire.Get: cursor not found');

    if vNumberReturned = 0 then
      raise Exception.Create('MongoWire.Get: no documents returned');

    Result := FDecoder.Decode(vStream);

    if (vFlags and $0002) <> 0 then
      raise Exception.Create('MongoWire.Get: '+VarToStr(Result.Items['$err'].Value));

///    Result := TWriteResult.Create(Self, DB, FRequestId);
  finally
    vStream.Free;
  end;
end;

function TDefaultMongoProvider.GetLastError(DB: String; RequestId: Integer): ICommandResult;
begin
  if (RequestId > 0) and (RequestId <> FRequestId) then
  begin
    Result := nil;
    Exit;
  end;
  Result := RunCommand(DB, TBSONObject.NewFrom('getlasterror', 1));
end;

function TDefaultMongoProvider.Insert(DB, Collection: String;BSONObject: IBSONObject): IWriteResult;
var
  vLength: Integer;
  vStream: TBSONStream;
begin
  InterlockedIncrement(FRequestId);

  vStream := TBSONStream.Create;
  try
    vStream.Clear;
    vStream.WriteInt(0); //length
    vStream.WriteInt(FRequestId);
    vStream.WriteInt(0);//ResponseTo
    vStream.WriteInt(OP_INSERT);
    vStream.WriteInt(0);//Flagss
    vStream.WriteUTF8String(Format('%s.%s', [DB, Collection]));

    FEncoder.SetBuffer(vStream);
    FEncoder.Encode(BSONObject);

    vLength := vStream.Size;
    vStream.WriteInt(0, vLength);

    SendBuf(vStream.Memory, vLength);

    Result := TWriteResult.Create(Self, DB, FRequestId);
  finally
    vStream.Free;
  end;
end;

procedure TDefaultMongoProvider.Connect(AHost: AnsiString; APort: Integer);
begin
  Close;

  {$IFDEF SYNAPSE}
    FSocket.Connect(AHost, IntToStr(APort));
    if (FSocket.LastError <> 0) then
    begin
      raise EMongoConnectionFailureException.CreateResFmt(@sMongoConnectionFailureException, [AHost, APort]);
    end;
  {$ELSE}
    FSocket.RemoteHost := AHost;
    FSocket.RemotePort := TSocketPort(IntToStr(APort));
    FSocket.Open;

    if not FSocket.Connected then
      raise EMongoConnectionFailureException.CreateResFmt(@sMongoConnectionFailureException, [AHost, APort]);
  {$ENDIF}
end;

procedure TDefaultMongoProvider.ReadResponse(AStream: TBSONStream; ARequestId: Integer;var AFlags, ANumberReturned: Integer;var ACursorId: Int64);
const
  dSize=$10000;
var
  i,l: integer;
  buf:array[0..2] of integer;
  d:array[0..dSize-1] of byte;
begin
  repeat
    //MsgLength,RequestID,ResponseTo
    i := ReceiveBuf(buf[0],12);
    if i <> 12 then
      raise EMongoInvalidResponse.CreateResFmt(@sMongoInvalidResponse, [ARequestId]);

      if buf[2] = ARequestId then
      begin
        //forward start of header
        AStream.Position:=0;
        AStream.Write(buf[0],12);
        l:=buf[0]-12;
        while l>0 do
         begin
          if l<dSize then i:=l else i:=dSize;
          i:= ReceiveBuf(d[0],i);
          if i=0 then raise EMongoReponseAborted.CreateResFmt(@sMongoReponseAborted, [ARequestId]);
          AStream.Write(d[0],i);
          dec(l,i);
         end;
        //set position after message header
        if buf[0]<36 then
          AStream.Position:=buf[0]
        else
          AStream.Position:=36;
      end;
  until buf[2]= ARequestID;

  AStream.Position := 0;
  AStream.ReadInt;//Length,
  AStream.ReadInt;//RequestID
  AStream.ReadInt;//ResponseTo
  AStream.ReadInt;//OpCode

  AFlags := AStream.ReadInt;
  ACursorId := AStream.ReadInt64;//CursorId
  AStream.ReadInt;//StartingFrom

  ANumberReturned := AStream.ReadInt;
end;

function TDefaultMongoProvider.RunCommand(DB: String; Command: IBSONObject): ICommandResult;
var
  vBSON: IBSONObject;
begin
  vBSON := FindOne(DB, COMMAND_COLLECTION, Command);

  Result := TCommandResult.Create;
  Result.PutAll(vBSON);
end;

procedure TDefaultMongoProvider.SetDecoder(const ADecoder: IMongoDecoder);
begin
  FDecoder := ADecoder;
end;

procedure TDefaultMongoProvider.SetEncoder(const AEncoder: IMongoEncoder);
begin
  FEncoder := AEncoder;
end;

function TDefaultMongoProvider.ReceiveBuf(var Buffer; Length: Integer): Integer;
begin
  {$IFDEF SYNAPSE}
  Result := FSocket.RecvBuffer(@Buffer, Length);
  {$ELSE}
  Result := FSocket.ReceiveBuf(Buffer, Length);
  {$ENDIF}
end;

function TDefaultMongoProvider.SendBuf(Buffer: Pointer; Length: Integer): Integer;
begin
  {$IFDEF SYNAPSE}
  Result := FSocket.SendBuffer(Buffer, Length);
  {$ELSE}
  Result := FSocket.SendBuf(Buffer^, Length);
  {$ENDIF}
end;

function TDefaultMongoProvider.OpenQuery(AStream: TBSONStream; DB, Collection: String;Query: IBSONObject; ASkip, ABatchSize: Integer): IBSONObject;
var
  vLength: Integer;
  vNumberReturned: Integer;
  vFlags:integer;
  vCursorId: Int64;
begin
  InterlockedIncrement(FRequestId);

  Result := TBSONObject.NewFrom('requestId', FRequestId);

  BeginMsg(AStream, DB, Collection, OP_QUERY);
  AStream.WriteInt(ASkip);
  AStream.WriteInt(ABatchSize);

  FEncoder.SetBuffer(AStream);
  FEncoder.Encode(Query);

  vLength := AStream.Size;
  AStream.WriteInt(0, vLength);

  SendBuf(AStream.Memory, vLength);

//    if ReturnFieldSelector<>nil then (ReturnFieldSelector as IPersistStream).Save(FData,false);
  ReadResponse(AStream, FRequestId, vFlags, vNumberReturned, vCursorId);

  Result.Put('numberReturned', vNumberReturned);
  Result.Put('cursorId', vCursorId);

  if (vFlags and $0001) <> 0 then
    raise Exception.Create('MongoWire.Get: cursor not found');

  if vNumberReturned = 0 then
    raise Exception.Create('MongoWire.Get: no documents returned');
end;

function TDefaultMongoProvider.HasNext(AStream: TBSONStream; DB, Collection: String; ACursorId: Int64; ABatchSize: Integer): IBSONObject;
var
  vLength, vFlags, vNumberReturned: Integer;
  vCursorId: Int64;
  vHasNext: Boolean;
begin
  vHasNext := False;
  vFlags := 0;
  vNumberReturned := 0;
  vCursorId := 0;

  if ACursorId > 0 then
  begin
    InterlockedIncrement(FRequestId);

    BeginMsg(AStream, DB, Collection, OP_GET_MORE);

    AStream.WriteInt(ABatchSize);
    AStream.WriteInt64(ACursorId);

    vLength := AStream.Size;
    AStream.WriteInt(0, vLength);

    SendBuf(AStream.Memory, vLength);

    ReadResponse(AStream, FRequestId, vFlags, vNumberReturned, vCursorId);

    vHasNext := vNumberReturned <> 0;

    if (vFlags and $0001)<>0 then raise
      Exception.Create('Query: cursor not found');
  end;

  Result := TBSONObject.NewFrom('requestId', FRequestId)
                       .Put('hasNext', vHasNext)
                       .Put('numberReturned', vNumberReturned)
                       .Put('cursorId', vCursorId);

end;

procedure TDefaultMongoProvider.BeginMsg(AStream: TBSONStream; DB, Collection: String; OperationCode: Integer);
begin
  AStream.Clear;
  AStream.WriteInt(0); //length
  AStream.WriteInt(FRequestId);
  AStream.WriteInt(0);//ResponseTo
  AStream.WriteInt(OperationCode);
  AStream.WriteInt(0);//Flags
  AStream.WriteUTF8String(Format('%s.%s', [DB, Collection]));
end;

procedure TDefaultMongoProvider.ReadResponse(AStream: TBSONStream;ARequestId: Integer; var AFlags, ANumberReturned: Integer);
var
  vCursorId: Int64;
begin
  ReadResponse(AStream, ARequestId, AFlags, ANumberReturned, vCursorId);
end;

{ TWriteResult }


constructor TWriteResult.Create(const AProvider: IMongoProvider; ADB: String; ARequestId: Integer);
begin
  FProvider := AProvider;
  FDB := ADB;
  FRequestId := ARequestId;
end;

function TWriteResult.getCachedLastError: ICommandResult;
begin
  Result := ICommandResult(FLastErrorResult);
end;

function TWriteResult.getLastError: ICommandResult;
begin
  if Assigned(FLastErrorResult) then
  begin
    Result := FLastErrorResult
  end
  else
  begin
    Result := FProvider.GetLastError(FDB, FRequestId);

    FLastErrorResult := Result;
  end;
end;

{ TCommandResult }

function TCommandResult.GetCode: Integer;
var
  vCode: TBSONItem;
begin
  Result := -1;

  vCode := Find('code');

  if (vCode <> nil) then
  begin
    Result := vCode.Value;
  end;
end;

function TCommandResult.GetErrorMessage: String;
var
  vErrorMsg: TBSONItem;
begin
  vErrorMsg := Find('errmsg');

  Result := EmptyStr;
  if Assigned(vErrorMsg) then
  begin
    Result := vErrorMsg.AsString;
  end;
end;

function TCommandResult.GetException: Exception;
var
  cmdName,
  vMessage: String;
  vError: TBSONItem;
  vCode: Integer;
begin
  Result := nil;
  
  if not Ok then
  begin
    cmdName := Item[0].AsString;

    vMessage := Format('command failed [%s]' + sLineBreak{  + Self.ToString}, [cmdName]);

    Result := ECommandFailure.Create(vMessage);
  end
  else
  begin
    // GLE check
    if HasError then
    begin
      vError := Items['err'];

      vCode := getCode();

      if (vCode = 11000) or (vCode = 11001) or (Pos('E11000', vError.AsString) = 1) or (Pos('E11001', vError.AsString) = 1) then
        Result := EMongoDuplicateKey.Create(vCode, vError.AsString)
      else
        Result := EMongoException.Create(vCode, vError.AsString);
    end;
  end;
end;

function TCommandResult.HasError: Boolean;
var
  vOK: TBSONItem;
begin
  vOK := Items['err'];

  Result := Length(vOK.AsString) > 1;
end;

function TCommandResult.Ok: Boolean;
var
  vOK: TBSONItem;
begin
  vOK := Items['ok'];

  Result := (vOK.Value = True) or (vOK.Value = Ord(True));
end;

procedure TCommandResult.RaiseOnError;

  function ReturnAddr: Pointer;
  asm
          MOV     EAX,[EBP+4]
  end;
  
var
  vException: Exception;
begin
  if (not Ok) or HasError then
  begin
    vException := GetException;

    if (vException <> nil) then
    begin
      raise vException at ReturnAddr; 
    end;
  end;
end;

end.
unit uLichessBot;

interface

uses
  SysUtils,
  Generics.Collections,

  uTypes,
  uFileLogger,
  uTimeSpan,
  uPipedExternalApplication;

type
  TBotState = (bsNone, bsTryingStart, bsStartFailed, bsLetterFailed, bsStarted, bsStopped);

  TLichessBot = class
  private
    FFileName: TFileName;
    FFileDateTime: TDateTime;
    FFileSize: U8;
    FErrorCount: UG;
    FFailCount: UG;
    FId: string;
    FName: string;
    FInitializationTime: TTimeSpan;
    FLogger: TFileLogger;
    FAllocatedMemoryPeak: U8;
    FExternalApplication: TPipedExternalApplication;
    FRequiredStart: BG;
    FQueuedGames: UG;
    FUsedGames: UG;
    FRequiredStop: BG;
    FPlayedGames: UG;
    FState: TBotState;
    FValueErrorCount: UG;

    procedure Clear;

    procedure OnReadLine(const AText: string);
    function GetContainsError(const ALowerCaseText: string): BG;

    procedure SetFileDateTime(const Value: TDateTime);
    procedure SetFileName(const Value: TFileName);
    procedure SetFileSize(const Value: U8);
    procedure SetRequiredStart(const Value: BG);
    procedure SetRequiredStop(const Value: BG);
    procedure SetState(const Value: TBotState);
    procedure SetValueErrorCount(const Value: UG);
  public
    constructor Create;
    destructor Destroy; override;

    // Input
    property FileName: TFileName read FFileName write SetFileName;
    property FileDateTime: TDateTime read FFileDateTime write SetFileDateTime;
    property FileSize: U8 read FFileSize write SetFileSize;
    property RequiredStart: BG read FRequiredStart write SetRequiredStart;
    property RequiredStop: BG read FRequiredStop write SetRequiredStop;

    // Output
    property Name: string read FName;
    property InitializationTime: TTimeSpan read FInitializationTime;
    property Logger: TFileLogger read FLogger;
    property AllocatedMemoryPeak: U8 read FAllocatedMemoryPeak;
    property ExternalApplication: TPipedExternalApplication read FExternalApplication;
    property ValueErrorCount: UG read FValueErrorCount write SetValueErrorCount;
    property ErrorCount: UG read FErrorCount;
    property FailCount: UG read FFailCount;
    property QueuedGames: UG read FQueuedGames;
    property UsedGames: UG read FUsedGames;
    property PlayedGames: UG read FPlayedGames;
    property State: TBotState read FState write SetState;

    // Process
    procedure ForceStart;
    procedure ForceStop;

    procedure Start;
    procedure Restart;
    procedure Stop;
    procedure AddFail;
  end;

  TLichessBots = TObjectList<TLichessBot>;

implementation

uses
  uFiles,
  uStrings,
  uMainTimer,
  uStartupWindowState,
  uExternalApplication;

{ TLichessBot }

procedure TLichessBot.AddFail;
begin
  Inc(FFailCount);
  if FLogger.IsLoggerFor(mlFatalError) then
    FLogger.Add('Failed to start', mlFatalError);
end;

function TLichessBot.GetContainsError(const ALowerCaseText: string): BG;
begin
  // i. e. socket error, trying to reconnect
  Result := Pos('error', ALowerCaseText) <> 0;
end;

procedure TLichessBot.Clear;
begin
  FQueuedGames := 0;
  FUsedGames := 0;
  FState := bsNone;
end;

constructor TLichessBot.Create;
var
  StartupWindowState: TStartupWindowState;
begin
  inherited;

  FExternalApplication := TPipedExternalApplication.Create;
  FExternalApplication.StartupType := stConsoleApplication;
  StartupWindowState.Active := False;
  StartupWindowState.WindowState := hwsNormal;
  FExternalApplication.StartupWindowState := StartupWindowState;
  FExternalApplication.OnReadLine := OnReadLine;
end;

destructor TLichessBot.Destroy;
begin
  try
    try
      ForceStop;
    finally
      FreeAndNil(FExternalApplication);
      Flogger.Free;
    end;
  finally
    inherited;
  end;
end;

procedure TLichessBot.OnReadLine(const AText: string);
const
  TotalUsedStr = 'Total Used: ';
  TotalQueuedStr = 'Total Queued: ';
var
  ALowerCaseText: string;
  ContainsError: BG;
  InTextIndex: SG;
  LastUsedGames: UG;
begin
  ALowerCaseText := LowerCase(AText);
  ContainsError := GetContainsError(ALowerCaseText);
  if Pos('valueerror', ALowerCaseText) <> 0 then
  begin
    Inc(FValueErrorCount);
  end
  else if ContainsError then
  begin
    Inc(FErrorCount);
  end
  else if Pos('you''re now connected', ALowerCaseText) <> 0 then
    FState := bsStarted
  else
  begin
    InTextIndex := Pos(TotalQueuedStr, AText);
    if InTextIndex <> 0 then
    begin
      FQueuedGames := ReadSGFast(AText, InTextIndex);
      Inc(InTextIndex, Length(TotalQueuedStr));
    end;

    InTextIndex := Pos(TotalUsedStr, AText);
    if InTextIndex <> 0 then
    begin
      Inc(InTextIndex, Length(TotalUsedStr));
      LastUsedGames := FUsedGames;
      FUsedGames := ReadSGFast(AText, InTextIndex);
      if FUsedGames > LastUsedGames then
        Inc(FPlayedGames, FUsedGames - LastUsedGames);
    end;
  end;

  if ContainsError then
  begin
    if FLogger.IsLoggerFor(mlError) then
      FLogger.Add(AText, mlError)
  end
  else
  begin
    if FLogger.IsLoggerFor(mlInformation) then
      FLogger.Add(AText, mlInformation);
  end;
end;

procedure TLichessBot.Restart;
begin
  Stop;
  Start;
end;

procedure TLichessBot.ForceStart;
var
  StartTime: TTimeSpan;
begin
  if FExternalApplication.Running then
    Exit;

  FInitializationTime.Ticks := 0;
  Clear;
  FExternalApplication.FileName := 'python.exe';
  FExternalApplication.Parameters := 'lichess-bot.py --config "' + FFileName + '"';
  FExternalApplication.CurrentDirectory := ExtractFilePath(FFileName);
  FExternalApplication.StartupType := stConsoleApplication;
  FExternalApplication.ConsoleStartupWindow := cswNoWindow;
  FExternalApplication.ConsoleCreateNewProcessGroup := True;

  try
    try
      StartTime := MainTimer.Value;
      FExternalApplication.Execute;
      FInitializationTime := MainTimer.IntervalFrom(StartTime);
      FExternalApplication.CheckErrorCode;
      if FLogger.IsLoggerFor(mlInformation) then
        FLogger.Add('Started', mlInformation);
    except
      on E: Exception do
      begin
        if FLogger.IsLoggerFor(mlFatalError) then
          FLogger.Add(E.Message, mlFatalError);
      end;
    end;
  finally
    FAllocatedMemoryPeak := FExternalApplication.AllocatedMemoryPeak;
  end;
end;

procedure TLichessBot.ForceStop;
begin
  FRequiredStart := False;
  FRequiredStop := False;
  Clear;
  if FLogger.IsLoggerFor(mlInformation) then
    FLogger.Add('Stopped', mlInformation);
  if FExternalApplication.Running then
  begin
    try
      FExternalApplication.Close;
      FExternalApplication.WaitFor;
    except
      on E: Exception do
      begin
        if FLogger.IsLoggerFor(mlError) then
          FLogger.Add(E.Message, mlError);
        FExternalApplication.TerminateAndWaitFor;
      end;
    end;
  end;
end;

procedure TLichessBot.SetFileDateTime(const Value: TDateTime);
begin
  FFileDateTime := Value;
end;

procedure TLichessBot.SetFileName(const Value: TFileName);
begin
  if FFileName <> Value then
  begin
    FFileName := Value;
    FName := DelFileExt(ExtractFileName(Value));
    FId := LegalFileName(FName);
    FLogger := TFileLogger.Create(LocalAppDataDir + FId + '.log');
  end;
end;

procedure TLichessBot.SetFileSize(const Value: U8);
begin
  FFileSize := Value;
end;

procedure TLichessBot.SetRequiredStart(const Value: BG);
begin
  FRequiredStart := Value;
end;

procedure TLichessBot.SetRequiredStop(const Value: BG);
begin
  FRequiredStop := Value;
end;

procedure TLichessBot.SetState(const Value: TBotState);
begin
  FState := Value;
end;

procedure TLichessBot.SetValueErrorCount(const Value: UG);
begin
  FValueErrorCount := Value;
end;

procedure TLichessBot.Start;
begin
  FRequiredStart := True;
end;

procedure TLichessBot.Stop;
begin
  if FUsedGames = 0 then
    ForceStop
  else
    FRequiredStop := True;
end;

end.

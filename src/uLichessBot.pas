unit uLichessBot;

interface

uses
  Classes,
  SysUtils,
  Generics.Collections,

  uTypes,
  uFileLogger,
  uTimeSpan,
  uPipedExternalApplication,
  uProcessMemory;

type
  TBotState = (bsStopped, bsTryingStart, bsStartFailed, bsTerminatedUnexpectly, bsStarted);

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
    FExternalApplication: TPipedExternalApplication;
    FRequiredStart: BG;
    FQueuedGames: UG;
    FUsedGames: SG;
    FRequiredStop: BG;
    FPlayedGames: UG;
    FState: TBotState;
    FValueErrorCount: UG;
    FLastGameDate: TDateTime;
    FOnChange: TNotifyEvent;
    FProcessMemoryCounters: TProcessMemoryCounters;
    procedure UpdateProcessMemoryCounters;

    procedure Clear;
    procedure Changed;

    procedure OnReadLine(const AText: string);
    procedure ParseGames(const AText: string);
    procedure ParseInformationalText(const AText: string);

    function GetWebAddress: string;
    function GetContainsError(const ALowerCaseText: string): BG;
    function GetNameFromFile(const AFileName: TFileName): string;

    procedure SetFileDateTime(const Value: TDateTime);
    procedure SetFileName(const Value: TFileName);
    procedure SetFileSize(const Value: U8);
    procedure SetRequiredStart(const Value: BG);
    procedure SetRequiredStop(const Value: BG);
    procedure SetState(const Value: TBotState);
    procedure SetValueErrorCount(const Value: UG);
    procedure ParseErrorText(const AText: string);
    procedure SetOnChange(const Value: TNotifyEvent);
    function GetProcessMemoryCounters: TProcessMemoryCounters;
  public
    constructor Create;
    destructor Destroy; override;

    // Input
    property FileName: TFileName read FFileName write SetFileName;
    property FileDateTime: TDateTime read FFileDateTime write SetFileDateTime;
    property FileSize: U8 read FFileSize write SetFileSize;
    property RequiredStart: BG read FRequiredStart write SetRequiredStart;
    property RequiredStop: BG read FRequiredStop write SetRequiredStop;
    property OnChange: TNotifyEvent read FOnChange write SetOnChange;

    // Output
    property Name: string read FName;
    property InitializationTime: TTimeSpan read FInitializationTime;
    property Logger: TFileLogger read FLogger;
    property ProcessMemoryCounters: TProcessMemoryCounters read GetProcessMemoryCounters;
    property ExternalApplication: TPipedExternalApplication read FExternalApplication;
    property ValueErrorCount: UG read FValueErrorCount write SetValueErrorCount;
    property ErrorCount: UG read FErrorCount;
    property FailCount: UG read FFailCount;
    property QueuedGames: UG read FQueuedGames;
    property UsedGames: SG read FUsedGames;
    property PlayedGames: UG read FPlayedGames;
    property LastGameDate: TDateTime read FLastGameDate;
    property State: TBotState read FState write SetState;
    property WebAddress: string read GetWebAddress;

    // Process
    procedure ForceStart;
    procedure ForceStop;

    procedure Start;
    procedure Restart;
    procedure Stop;
    procedure AddFail(const ALogMessageText: string);
    procedure ClearErrors;
    procedure ClearGames;
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

procedure TLichessBot.AddFail(const ALogMessageText: string);
begin
  Inc(FFailCount);
  if FLogger.IsLoggerFor(mlFatalError) then
    FLogger.Add(ALogMessageText, mlFatalError);
  Changed;
end;

procedure TLichessBot.ParseErrorText(const AText: string);
begin
  if Pos('valueerror', AText) <> 0 then
  begin
    // Skip, happen if connection is lost
    if Pos('valueerror: invalid literal for int() with base 16: b''', AText) = 0 then
      Inc(FValueErrorCount);
  end
  else
    Inc(FErrorCount);
  Changed;
end;

procedure TLichessBot.ParseInformationalText(const AText: string);
begin
  if Pos('you''re now connected', AText) <> 0 then
  begin
    FState := bsStarted;
    Changed;
  end
  else
  begin
    ParseGames(AText);
  end;
end;

function TLichessBot.GetProcessMemoryCounters: TProcessMemoryCounters;
begin
  UpdateProcessMemoryCounters;
  Result := FProcessMemoryCounters;
end;

function TLichessBot.GetContainsError(const ALowerCaseText: string): BG;
begin
  // i. e. socket error, trying to reconnect
  Result := Pos('error', ALowerCaseText) <> 0;
end;

function TLichessBot.GetNameFromFile(const AFileName: TFileName): string;
const
  Prefix = 'name: "';
var
  s: string;
  Index: SG;
begin
  ReadStringFromFile(AFileName, s);
  Index := Pos(Prefix, s);
  if Index > 0 then
  begin
    Inc(Index, Length(Prefix));
    Result := ReadToChar(s, Index, '"');
  end
  else
    Result := '';
end;

function TLichessBot.GetWebAddress: string;
begin
  Result := 'https://lichess.org/@/' + DelFileExt(ExtractFileName(FFileName)) + '/all';
end;

procedure TLichessBot.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TLichessBot.Clear;
begin
  FQueuedGames := 0;
  FUsedGames := 0;
  FState := bsStopped;
  Changed;
end;

procedure TLichessBot.ClearErrors;
begin
  FFailCount := 0;
  FErrorCount := 0;
  FValueErrorCount := 0;
  Changed;
end;

procedure TLichessBot.ClearGames;
begin
  FPlayedGames := 0;
  Changed;
end;

constructor TLichessBot.Create;
var
  StartupWindowState: TStartupWindowState;
begin
  inherited;

  FExternalApplication := TPipedExternalApplication.Create;
  FExternalApplication.FileName := 'python.exe';
  FExternalApplication.StartupType := stConsoleApplication;
  FExternalApplication.ConsoleStartupWindow := cswNoWindow;
  FExternalApplication.ConsoleCreateNewProcessGroup := False;
  FExternalApplication.ProcessPriority := ppBelowNormal;
  StartupWindowState.Active := False;
  StartupWindowState.WindowState := hwsNormal;
  FExternalApplication.StartupWindowState := StartupWindowState;
  FExternalApplication.OnReadLine := OnReadLine;
end;

destructor TLichessBot.Destroy;
begin
  try
    try
      FOnChange := nil;
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
var
  ALowerCaseText: string;
  LogLevel: TMessageLevel;
begin
  ALowerCaseText := LowerCase(AText);
  if GetContainsError(ALowerCaseText) then
    LogLevel := mlError
  else
    LogLevel := mlInformation;

  if FLogger.IsLoggerFor(LogLevel) then
    FLogger.Add(AText, LogLevel);

  if LogLevel = mlError then
  begin
    ParseErrorText(ALowerCaseText);
  end
  else
  begin
    ParseInformationalText(ALowerCaseText);
  end;
end;

procedure TLichessBot.ParseGames(const AText: string);
var
  InTextIndex: SG;
  LastUsedGames: SG;
const
  TotalQueuedStr = 'total queued: ';
  TotalUsedStr = 'total used: ';
begin
  InTextIndex := Pos(TotalQueuedStr, AText);
  if InTextIndex <> 0 then
  begin
    Inc(InTextIndex, Length(TotalQueuedStr));
    FQueuedGames := ReadSGFast(AText, InTextIndex);
  end;
  InTextIndex := Pos(TotalUsedStr, AText);
  if InTextIndex <> 0 then
  begin
    Inc(InTextIndex, Length(TotalUsedStr));
    LastUsedGames := FUsedGames;
    FUsedGames := ReadSGFast(AText, InTextIndex);
    if FUsedGames <> LastUsedGames then
    begin
      if FUsedGames > LastUsedGames then
      begin
        FLastGameDate := Now;
        Inc(FPlayedGames, FUsedGames - LastUsedGames);
      end;
      UpdateProcessMemoryCounters;
    end;
  end;
  Changed;
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

  Clear;
  FState := bsTryingStart;
  Changed;
  FExternalApplication.Parameters := 'lichess-bot.py --config "' + FFileName + '"';
  FExternalApplication.CurrentDirectory := ExtractFilePath(FFileName);
  try
    FInitializationTime.Ticks := 0;
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
end;

procedure TLichessBot.ForceStop;
begin
  FRequiredStart := False;
  FRequiredStop := False;
  Clear;
  if FExternalApplication.Running then
  begin
    if FLogger.IsLoggerFor(mlInformation) then
      FLogger.Add('Stopped', mlInformation);
    FExternalApplication.TerminateProcessTree; // Hotfix, python do not stop all child processes
{    try
      FExternalApplication.Close;
      FExternalApplication.WaitFor;
    except
      on E: Exception do
      begin
        if FLogger.IsLoggerFor(mlError) then
          FLogger.Add(E.Message, mlError);
        FExternalApplication.TerminateProcessTree;
      end;
    end;}
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
    FName := GetNameFromFile(FFileName);
    FId := LegalFileName(FName);
    FLogger := TFileLogger.Create(LocalAppDataDir + FId + '.log');
  end;
end;

procedure TLichessBot.SetFileSize(const Value: U8);
begin
  FFileSize := Value;
end;

procedure TLichessBot.SetOnChange(const Value: TNotifyEvent);
begin
  FOnChange := Value;
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
  Changed;
end;

procedure TLichessBot.Stop;
begin
  if FUsedGames = 0 then
    ForceStop
  else
  begin
    FRequiredStop := True;
    Changed;
  end;
end;

procedure TLichessBot.UpdateProcessMemoryCounters;
var
  Actual: TProcessMemoryCounters;
begin
  Actual := GetProcessMemoryCountersRecursive(FExternalApplication.ProcessId);
  FProcessMemoryCounters.Update(Actual);
end;

end.

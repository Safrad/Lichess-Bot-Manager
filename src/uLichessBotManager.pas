unit uLichessBotManager;

interface

uses
  Classes,
  SysUtils,

  uTypes,
  uLichessBot,
  uSxThreadTimer;

type
  TLichessBotManager = class
  private
    FLichessBots: TLichessBots;
    FRootDirectory: string;
    FSxThreadTimer: TSxThreadTimer;
    FRestartBotIfFails: BG;
    FOnChange: TNotifyEvent;
    procedure TryAddLichessBot(const AFileName: TFileName; const AFileSize: U8; const AFileDate: TDateTime);
    procedure SetRootDirectory(const Value: string);
    procedure RWOptions(const ASave: BG);
    function GetRunningBotCount: UG;

    procedure OnTimerEvent(Sender: TObject);
    procedure Changed;

    procedure SetRestartBotIfFails(const Value: BG);
    procedure StopAlRunningAndNotPlayingBots;
    procedure CheckBotsIfNotFailed;
    procedure AbortStartOfAllBots;
    procedure StartOneBot;
    function IsSomeBotTryingToStart: BG;
    procedure CreateTimer;
    procedure CheckBotIfNotFailed(Bot: TLichessBot);
    procedure SetOnChange(const Value: TNotifyEvent);
  public
    constructor Create;
    destructor Destroy; override;

    // Input
    property RootDirectory: string read FRootDirectory write SetRootDirectory;
    property RestarnBotIfFails: BG read FRestartBotIfFails write SetRestartBotIfFails;
    property OnChange: TNotifyEvent read FOnChange write SetOnChange;

    // Process
    procedure AddLichesBotsFromRootFolder;
    function FindBot(const AFileName: TFileName): BG;
    procedure StartAll;
    procedure StopAll;

    // Output
    property LichessBots: TLichessBots read FLichessBots;
    property RunningBotCount: UG read GetRunningBotCount;
  end;

implementation

uses
  uFolder,
  uMsg,
  uFiles,
  uDIniFile;

{ TLichessBotManager }

constructor TLichessBotManager.Create;
begin
  inherited;

  FRestartBotIfFails := True;

  FLichessBots := TLichessBots.Create;
  FLichessBots.OwnsObjects := True;

  RWOptions(False);

  CreateTimer;
end;

destructor TLichessBotManager.Destroy;
begin
  try
    FreeAndNil(FSxThreadTimer);
    RWOptions(True);
    FLichessBots.Free;
  finally
    inherited;
  end;
end;

function TLichessBotManager.FindBot(const AFileName: TFileName): BG;
var
  Bot: TLichessBot;
begin
  for Bot in FLichessBots do
  begin
    if Bot.FileName = AFileName then
    begin
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

function TLichessBotManager.GetRunningBotCount: UG;
var
  Bot: TLichessBot;
begin
  Result := 0;
  for Bot in FLichessBots do
  begin
    if Bot.ExternalApplication.Running then
      Inc(Result);
  end;
end;

procedure TLichessBotManager.OnTimerEvent(Sender: TObject);
begin
  StopAlRunningAndNotPlayingBots;

  CheckBotsIfNotFailed;

  if IsSomeBotTryingToStart then
    Exit;

  StartOneBot;
end;

procedure TLichessBotManager.RWOptions(const ASave: BG);
const
  Section = 'Bots';
begin
  MainIni.RWString(Section, 'RootDirectory', FRootDirectory, ASave);
  MainIni.RWBool(Section, 'RestartBotFails', FRestartBotIfFails, ASave);
end;

procedure TLichessBotManager.AddLichesBotsFromRootFolder;
var
  Folder: TFolder;
  FileItem: TFileItem;
  i: SG;
begin
  if FRootDirectory = '' then
    raise Exception.Create('Please set lichess bot root directory (contains *.yml files).');

  Folder := TFolder.Create;
  try
    Folder.AcceptDirs := False;
    Folder.AcceptFiles := True;
    Folder.SubDirs := True;
    Folder.Path := FRootDirectory;
    Folder.Extensions := ['yml'];
    Folder.Read;

    for i := 0 to Folder.Count - 1 do
    begin
      FileItem := TFileItem(Folder.Files.GetObject(i));
      TryAddLichessBot(FRootDirectory + FileItem.Name, FileItem.Size, FileItem.DateTime);
    end;
  finally
    Folder.Free;
  end;

  if FLichessBots.Count = 0 then
    Information('No yml files found, select different folder.');
end;

procedure TLichessBotManager.SetOnChange(const Value: TNotifyEvent);
begin
  FOnChange := Value;
end;

procedure TLichessBotManager.SetRestartBotIfFails(const Value: BG);
begin
  FRestartBotIfFails := Value;
end;

procedure TLichessBotManager.SetRootDirectory(const Value: string);
begin
  FRootDirectory := Value;
end;

procedure TLichessBotManager.StartAll;
var
  Bot: TLichessBot;
begin
  for Bot in FLichessBots do
  begin
    Bot.RequiredStart := True;
  end;
end;

procedure TLichessBotManager.StopAll;
var
  Bot: TLichessBot;
begin
  for Bot in FLichessBots do
  begin
    Bot.Stop;
  end;
end;

procedure TLichessBotManager.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TLichessBotManager.CheckBotIfNotFailed(Bot: TLichessBot);
begin
  if (Bot.State in [bsTryingStart, bsStarted]) and (not Bot.ExternalApplication.Running) then
  begin
    if Bot.State = bsTryingStart then
    begin
      Bot.State := bsStartFailed;
      AbortStartOfAllBots;
      Bot.AddFail('Failed to start bot');
    end
    else
    begin
      Bot.State := bsLetterFailed;
      if FRestartBotIfFails then
      begin
        Bot.AddFail('Bot terminated unexpectly, I will try to start it again');
        Bot.RequiredStart := True;
      end
      else
        Bot.AddFail('Bot terminated unexpectly');
    end;
    Changed;
  end;
end;

procedure TLichessBotManager.CreateTimer;
begin
  FSxThreadTimer := TSxThreadTimer.Create;
  FSxThreadTimer.Interval.Seconds := 15;
  FSxThreadTimer.OnTimer := OnTimerEvent;
  FSxThreadTimer.Enabled := True;
end;

function TLichessBotManager.IsSomeBotTryingToStart: BG;
var
  Bot: TLichessBot;
begin
  for Bot in FLichessBots do
  begin
    if Bot.State = bsTryingStart then
    begin
      // Wait, do not try to start another bot
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

procedure TLichessBotManager.StartOneBot;
var
  Bot: TLichessBot;
begin
  for Bot in FLichessBots do
  begin
    if Bot.RequiredStart then
    begin
      Bot.RequiredStart := False;
      Bot.ForceStart;
      // Wait before start next bot
      Break;
    end;
  end;
end;

procedure TLichessBotManager.AbortStartOfAllBots;
var
  Bot: TLichessBot;
begin
  // Do not try other bots
  for Bot in FLichessBots do
    Bot.RequiredStart := False;
end;

procedure TLichessBotManager.CheckBotsIfNotFailed;
var
  Bot: TLichessBot;
begin
  for Bot in FLichessBots do
  begin
    CheckBotIfNotFailed(Bot);
  end;
end;

procedure TLichessBotManager.StopAlRunningAndNotPlayingBots;
var
  Bot: TLichessBot;
begin
  for Bot in FLichessBots do
  begin
    if (Bot.RequiredStop) and (Bot.UsedGames = 0) then
    begin
      Bot.RequiredStop := False;
      Bot.ForceStop;
    end;
  end;
end;

procedure TLichessBotManager.TryAddLichessBot(const AFileName: TFileName; const AFileSize: U8; const AFileDate: TDateTime);
var
  Bot: TLichessBot;
begin
  if FindBot(AFileName) = False then
  begin
    Bot := TLichessBot.Create;
    try
      Bot.FileName := AFileName;
      Bot.FileSize := AFileSize;
      Bot.FileDateTime := AFileDate;
      Bot.OnChange := OnChange;
      FLichessBots.Add(Bot);
    except
      Bot.Free;
      raise;
    end;
  end;
end;

end.

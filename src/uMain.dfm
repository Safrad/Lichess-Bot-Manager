object fMain: TfMain
  Left = 0
  Top = 0
  Width = 868
  Height = 470
  AutoScroll = True
  Caption = 'Lichess Bot Manager'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Menu = MainMenu1
  OldCreateOrder = False
  OnClose = FormClose
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 13
  object DView1: TDView
    Left = 0
    Top = 0
    Width = 852
    Height = 411
    Align = alClient
    Zoom = 1.000000000000000000
    EnableZoom = True
    DisplayMode = dmCustom
    PopupMenu = PopupMenu1
    TabOrder = 0
    OnDblClick = DView1DblClick
    OnGetDataEx = DView1GetDataEx
  end
  object MainMenu1: TMainMenu
    Left = 16
    object File1: TMenuItem
      Caption = 'File'
      object ReloadBotFolder1: TMenuItem
        Caption = 'Add New Bots From Folder'
        OnClick = ReloadBotFolder1Click
      end
    end
    object SelectedBots1: TMenuItem
      Caption = 'Selected Bot(s)'
      object Start1: TMenuItem
        Caption = 'Start'
        OnClick = Start1Click
      end
      object Restart1: TMenuItem
        Caption = 'Restart'
        OnClick = Restart1Click
      end
      object Stop1: TMenuItem
        Caption = 'Stop'
        OnClick = Stop1Click
      end
      object N2: TMenuItem
        Caption = '-'
      end
      object ClearGames1: TMenuItem
        Caption = 'Clear Games'
        OnClick = ClearGames1Click
      end
      object ClearErrors1: TMenuItem
        Caption = 'Clear Errors'
        OnClick = ClearErrors1Click
      end
      object N1: TMenuItem
        Caption = '-'
      end
      object EditConfiguration1: TMenuItem
        Caption = 'Edit Configuration... Left Mouse Dbl Click (first 8 columns)'
        OnClick = BotConfiguration1Click
      end
      object OpenLogFile1: TMenuItem
        Caption = 'Open Log File.. Left Mouse Dbl Click (next 3 columns)'
        OnClick = OpenLogFile1Click
      end
      object OpenLichessBotWebPage1: TMenuItem
        Caption = 
          'Open Lichess Bot Web Page... Left Mouse Dbl Click (last 3 column' +
          's)'
        OnClick = OpenLichessBotWebPage1Click
      end
    end
    object Bots1: TMenuItem
      Caption = 'Bots'
      object StartAll1: TMenuItem
        Caption = 'Start All'
        OnClick = StartAll1Click
      end
      object StopAll1: TMenuItem
        Caption = 'Stop All'
        OnClick = StopAll1Click
      end
    end
    object Options1: TMenuItem
      Caption = 'Options'
      object EngineRootFolder1: TMenuItem
        Caption = 'Bot Root Folder...'
        ShortCut = 16464
        OnClick = EngineRootFolder1Click
      end
      object RestartBotIfFails1: TMenuItem
        Caption = 'Restart Bot If Fails'
        Checked = True
        OnClick = RestartBotIfFails1Click
      end
      object StartBotsAfterApplicationStart1: TMenuItem
        Caption = 'Start Bots After Application Starts'
        OnClick = StartBotsAfterApplicationStart1Click
      end
    end
    object Help1: TMenuItem
      Caption = 'Help'
    end
  end
  object PopupMenu1: TPopupMenu
    OnPopup = PopupMenu1Popup
    Left = 56
  end
end

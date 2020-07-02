object Frm_Item: TFrm_Item
  Left = 559
  Height = 395
  Top = 325
  Width = 423
  Caption = 'Frm_Item'
  ClientHeight = 395
  ClientWidth = 423
  Color = clBtnFace
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  LCLVersion = '2.1.0.0'
  object Label1: TLabel
    Left = 26
    Height = 14
    Top = 15
    Width = 29
    Alignment = taRightJustify
    Caption = 'Code'
    ParentColor = False
  end
  object Label2: TLabel
    Left = 23
    Height = 14
    Top = 47
    Width = 33
    Alignment = taRightJustify
    Caption = 'Name'
    ParentColor = False
  end
  object Label3: TLabel
    Left = 28
    Height = 14
    Top = 79
    Width = 26
    Alignment = taRightJustify
    Caption = 'Date'
    ParentColor = False
  end
  object Label4: TLabel
    Left = 22
    Height = 14
    Top = 103
    Width = 35
    Alignment = taRightJustify
    Caption = 'Image'
    ParentColor = False
  end
  object Image1: TImage
    Left = 56
    Height = 209
    Top = 104
    Width = 177
    ParentShowHint = False
    Proportional = True
    ShowHint = True
  end
  object edCode: TEdit
    Left = 56
    Height = 30
    Top = 8
    Width = 121
    TabOrder = 0
  end
  object edName: TEdit
    Left = 56
    Height = 30
    Top = 40
    Width = 337
    TabOrder = 1
  end
  object btnOK: TButton
    Left = 56
    Height = 25
    Top = 328
    Width = 75
    Caption = 'OK'
    ModalResult = 1
    TabOrder = 2
  end
  object btnCancel: TButton
    Left = 160
    Height = 25
    Top = 328
    Width = 75
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 3
  end
  object btnLoad: TButton
    Left = 237
    Height = 25
    Top = 288
    Width = 35
    Caption = 'Load'
    OnClick = btnLoadClick
    TabOrder = 4
  end
  object DateTimePicker: TDateTimePicker
    Left = 56
    Height = 20
    Top = 72
    Width = 87
    CenturyFrom = 1941
    MaxDate = 2958465
    MinDate = -53780
    TabOrder = 5
    TrailingSeparator = False
    LeadingZeros = True
    Kind = dtkDate
    TimeFormat = tf24
    TimeDisplay = tdHMS
    DateMode = dmComboBox
    Date = 40975
    Time = 0.964515833336918
    UseDefaultSeparators = True
    HideDateTimeParts = []
    MonthNames = 'Long'
  end
  object OpenPictureDialog1: TOpenPictureDialog
    Left = 240
    Top = 256
  end
end
